param(
    [string]$InputDir = (Join-Path $PSScriptRoot 'w4_data'),
    [string]$OutputDir = (Join-Path $PSScriptRoot 'output\w4_analysis')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Mean([double[]]$Values) {
    if ($Values.Count -eq 0) { return [double]::NaN }
    return ($Values | Measure-Object -Average).Average
}

function Get-SampleSd([double[]]$Values) {
    if ($Values.Count -lt 2) { return 0.0 }
    $mean = Get-Mean $Values
    $ss = 0.0
    foreach ($value in $Values) { $ss += ($value - $mean) * ($value - $mean) }
    return [Math]::Sqrt($ss / ($Values.Count - 1))
}

function Get-Median([double[]]$Values) {
    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -eq 0) { return [double]::NaN }
    $middle = [int][Math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2 -eq 1) { return $sorted[$middle] }
    return ($sorted[$middle - 1] + $sorted[$middle]) / 2.0
}

function Get-LinearFit($Points) {
    $x = [double[]]@($Points | ForEach-Object { $_.Length_um })
    $y = [double[]]@($Points | ForEach-Object { $_.MeanResistance_Ohm })
    $meanX = Get-Mean $x
    $meanY = Get-Mean $y
    $sxx = 0.0; $sxy = 0.0; $syy = 0.0
    for ($i = 0; $i -lt $x.Count; $i++) {
        $dx = $x[$i] - $meanX
        $dy = $y[$i] - $meanY
        $sxx += $dx * $dx
        $sxy += $dx * $dy
        $syy += $dy * $dy
    }
    $slope = $sxy / $sxx
    $intercept = $meanY - $slope * $meanX
    $r2 = if ($syy -gt 0) { ($sxy * $sxy) / ($sxx * $syy) } else { 1.0 }
    $residuals = [double[]]@($Points | ForEach-Object { $_.MeanResistance_Ohm - ($intercept + $slope * $_.Length_um) })
    $rmse = [Math]::Sqrt((($residuals | ForEach-Object { $_ * $_ } | Measure-Object -Sum).Sum) / [Math]::Max(1, $x.Count - 2))
    $violations = 0
    $ordered = @($Points | Sort-Object Length_um)
    for ($i = 1; $i -lt $ordered.Count; $i++) {
        if ($ordered[$i].MeanResistance_Ohm -lt $ordered[$i - 1].MeanResistance_Ohm) { $violations++ }
    }
    [pscustomobject]@{
        Slope_Ohm_per_um = $slope
        Intercept_Ohm = $intercept
        R2 = $r2
        RMSE_Ohm = $rmse
        MonotonicViolations = $violations
        PositiveStepFraction = 1.0 - ($violations / [Math]::Max(1, $ordered.Count - 1))
    }
}

function Parse-FileName([string]$Name) {
    if ($Name -match '^1strow_(\d+)um\.csv$') {
        return [pscustomobject]@{ Row = '1strow'; Bias_V = 0.01; Length_um = [int]$Matches[1]; Replicate = 1 }
    }
    if ($Name -match '^2ndrow_(\d+)um\.csv$') {
        return [pscustomobject]@{ Row = '2ndrow'; Bias_V = 0.01; Length_um = [int]$Matches[1]; Replicate = 1 }
    }
    if ($Name -match '^3rdrow_(0\.\d+)V_(\d+)um\.csv$') {
        return [pscustomobject]@{ Row = '3rdrow'; Bias_V = [double]$Matches[1]; Length_um = [int]$Matches[2]; Replicate = 1 }
    }
    if ($Name -match '^4throw_(\d+)um\.csv$') {
        return [pscustomobject]@{ Row = '4throw'; Bias_V = 0.01; Length_um = [int]$Matches[1]; Replicate = 1 }
    }
    if ($Name -match '^5throw_(\d+)um(?:_(\d+))?\.csv$') {
        $rep = if ($Matches[2]) { [int]$Matches[2] } else { 1 }
        return [pscustomobject]@{ Row = '5throw'; Bias_V = 0.01; Length_um = [int]$Matches[1]; Replicate = $rep }
    }
    return $null
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$fileSummary = @()
$excluded = @()
foreach ($file in Get-ChildItem -LiteralPath $InputDir -Filter '*.csv' | Sort-Object Name) {
    if ($file.Name -match '^1strow_.*_ver2\.csv$') {
        $excluded += [pscustomobject]@{ File = $file.Name; Reason = 'User decision: use original 1strow files only' }
        continue
    }
    $meta = Parse-FileName $file.Name
    if ($null -eq $meta) {
        $excluded += [pscustomobject]@{ File = $file.Name; Reason = 'Filename pattern not recognized' }
        continue
    }
    $data = @(Import-Csv -LiteralPath $file.FullName)
    $current = [double[]]@($data | ForEach-Object { [double]$_.Current })
    $voltage = [double[]]@($data | ForEach-Object { [double]$_.Voltage })
    $resistance = [double[]]@($data | ForEach-Object { [double]$_.Resistance })
    $recalculated = [double[]]@($data | ForEach-Object { [double]$_.Voltage / [double]$_.Current })
    $diff = [double[]]@((0..($resistance.Count - 1)) | ForEach-Object { [Math]::Abs($resistance[$_] - $recalculated[$_]) })
    $firstCount = [Math]::Min(10, $resistance.Count)
    $first = [double[]]@($resistance[0..($firstCount - 1)])
    $last = [double[]]@($resistance[($resistance.Count - $firstCount)..($resistance.Count - 1)])
    $sd = Get-SampleSd $resistance
    $meanR = Get-Mean $resistance
    $fileSummary += [pscustomobject]@{
        File = $file.Name
        Row = $meta.Row
        Bias_V = $meta.Bias_V
        Length_um = $meta.Length_um
        Replicate = $meta.Replicate
        N = $resistance.Count
        MeanCurrent_A = Get-Mean $current
        MeanVoltage_V = Get-Mean $voltage
        MeanResistance_Ohm = $meanR
        MedianResistance_Ohm = Get-Median $resistance
        SDResistance_Ohm = $sd
        SEMResistance_Ohm = $sd / [Math]::Sqrt($resistance.Count)
        CV_percent = 100.0 * $sd / $meanR
        First10Mean_Ohm = Get-Mean $first
        Last10Mean_Ohm = Get-Mean $last
        Drift_Ohm = (Get-Mean $last) - (Get-Mean $first)
        MeanAbsStoredVsVI_Ohm = Get-Mean $diff
    }
}

# Aggregate repeated runs by taking the mean of run-level means, so unequal sample counts do not change weights.
$conditionSummary = @()
$groups = $fileSummary | Group-Object Row, Bias_V, Length_um
foreach ($group in $groups) {
    $items = @($group.Group)
    $runMeans = [double[]]@($items | ForEach-Object { $_.MeanResistance_Ohm })
    $withinSd = [double[]]@($items | ForEach-Object { $_.SDResistance_Ohm })
    $conditionSummary += [pscustomobject]@{
        Row = $items[0].Row
        Bias_V = $items[0].Bias_V
        Length_um = $items[0].Length_um
        RunCount = $items.Count
        TotalSamples = ($items.N | Measure-Object -Sum).Sum
        MeanResistance_Ohm = Get-Mean $runMeans
        MeanWithinRunSD_Ohm = Get-Mean $withinSd
        BetweenRunSD_Ohm = if ($items.Count -gt 1) { Get-SampleSd $runMeans } else { 0.0 }
    }
}
$conditionSummary = @($conditionSummary | Sort-Object Row, Bias_V, Length_um)

$regressionSummary = @()
$seriesGroups = $conditionSummary | Group-Object Row, Bias_V
foreach ($group in $seriesGroups) {
    $points = @($group.Group | Sort-Object Length_um)
    $fit = Get-LinearFit $points
    $regressionSummary += [pscustomobject]@{
        Row = $points[0].Row
        Bias_V = $points[0].Bias_V
        PointCount = $points.Count
        Slope_Ohm_per_um = $fit.Slope_Ohm_per_um
        Intercept_Ohm = $fit.Intercept_Ohm
        R2 = $fit.R2
        RMSE_Ohm = $fit.RMSE_Ohm
        MonotonicViolations = $fit.MonotonicViolations
        PositiveStepFraction = $fit.PositiveStepFraction
        TheoryMatchScore = $fit.R2 * $fit.PositiveStepFraction
    }
}
$regressionSummary = @($regressionSummary | Sort-Object Bias_V, @{Expression='TheoryMatchScore';Descending=$true})

$best001 = $regressionSummary | Where-Object { [Math]::Abs($_.Bias_V - 0.01) -lt 1e-9 -and $_.Slope_Ohm_per_um -gt 0 } | Sort-Object TheoryMatchScore -Descending | Select-Object -First 1
$selected = @($regressionSummary | Where-Object { $_.Row -eq $best001.Row })

$fileSummary | Export-Csv -LiteralPath (Join-Path $OutputDir 'file_summary.csv') -NoTypeInformation -Encoding UTF8
$conditionSummary | Export-Csv -LiteralPath (Join-Path $OutputDir 'condition_summary.csv') -NoTypeInformation -Encoding UTF8
$regressionSummary | Export-Csv -LiteralPath (Join-Path $OutputDir 'regression_summary.csv') -NoTypeInformation -Encoding UTF8
$selected | Export-Csv -LiteralPath (Join-Path $OutputDir 'presentation_selection.csv') -NoTypeInformation -Encoding UTF8
$excluded | Export-Csv -LiteralPath (Join-Path $OutputDir 'excluded_files.csv') -NoTypeInformation -Encoding UTF8

Add-Type -AssemblyName System.Drawing

function New-Plot {
    param(
        [string]$Path,
        [string]$Title,
        [string]$Subtitle,
        [object[]]$Series,
        [double]$YMin,
        [double]$YMax,
        [bool]$ShowFits = $true
    )
    $width = 1600; $height = 1000
    $bitmap = New-Object System.Drawing.Bitmap($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $graphics.Clear([System.Drawing.Color]::White)

    $fontTitle = New-Object System.Drawing.Font('Arial', 28, [System.Drawing.FontStyle]::Bold)
    $fontSubtitle = New-Object System.Drawing.Font('Arial', 15)
    $fontAxis = New-Object System.Drawing.Font('Arial', 14)
    $fontTick = New-Object System.Drawing.Font('Arial', 12)
    $fontLegend = New-Object System.Drawing.Font('Arial', 13)
    $brushText = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(35, 42, 52))
    $brushMuted = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(90, 99, 110))
    $gridPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(225, 229, 235), 1)
    $axisPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(55, 65, 81), 2)

    $left = 135; $top = 135; $plotWidth = 1320; $plotHeight = 700
    $xMin = 10.0; $xMax = 50.0
    $mapX = { param([double]$x) $left + (($x - $xMin) / ($xMax - $xMin)) * $plotWidth }
    $mapY = { param([double]$y) $top + $plotHeight - (($y - $YMin) / ($YMax - $YMin)) * $plotHeight }

    $graphics.DrawString($Title, $fontTitle, $brushText, 65, 28)
    $graphics.DrawString($Subtitle, $fontSubtitle, $brushMuted, 68, 78)

    for ($i = 0; $i -le 5; $i++) {
        $yValue = $YMin + ($YMax - $YMin) * $i / 5.0
        $py = & $mapY $yValue
        $graphics.DrawLine($gridPen, $left, $py, $left + $plotWidth, $py)
        $label = ('{0:F1}' -f $yValue)
        $size = $graphics.MeasureString($label, $fontTick)
        $graphics.DrawString($label, $fontTick, $brushMuted, $left - $size.Width - 14, $py - $size.Height / 2)
    }
    foreach ($xValue in 10, 15, 20, 25, 30, 35, 40, 45, 50) {
        $px = & $mapX $xValue
        $graphics.DrawLine($gridPen, $px, $top, $px, $top + $plotHeight)
        $label = [string]$xValue
        $size = $graphics.MeasureString($label, $fontTick)
        $graphics.DrawString($label, $fontTick, $brushMuted, $px - $size.Width / 2, $top + $plotHeight + 12)
    }
    $graphics.DrawLine($axisPen, $left, $top, $left, $top + $plotHeight)
    $graphics.DrawLine($axisPen, $left, $top + $plotHeight, $left + $plotWidth, $top + $plotHeight)
    $xLabel = 'CTLM gap spacing (um)'
    $xSize = $graphics.MeasureString($xLabel, $fontAxis)
    $graphics.DrawString($xLabel, $fontAxis, $brushText, $left + ($plotWidth - $xSize.Width) / 2, $top + $plotHeight + 55)
    $graphics.TranslateTransform(35, $top + $plotHeight / 2)
    $graphics.RotateTransform(-90)
    $yLabel = 'Mean resistance (Ohm)'
    $ySize = $graphics.MeasureString($yLabel, $fontAxis)
    $graphics.DrawString($yLabel, $fontAxis, $brushText, -$ySize.Width / 2, 0)
    $graphics.ResetTransform()

    $legendX = 150; $legendY = 942
    $legendOffset = 0
    foreach ($series in $Series) {
        $color = [System.Drawing.ColorTranslator]::FromHtml($series.Color)
        $pen = New-Object System.Drawing.Pen($color, 3)
        $fitPen = New-Object System.Drawing.Pen($color, 2)
        $fitPen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
        $brush = New-Object System.Drawing.SolidBrush($color)
        $points = @($series.Points | Sort-Object Length_um)

        for ($i = 1; $i -lt $points.Count; $i++) {
            $graphics.DrawLine($pen, (& $mapX $points[$i - 1].Length_um), (& $mapY $points[$i - 1].MeanResistance_Ohm), (& $mapX $points[$i].Length_um), (& $mapY $points[$i].MeanResistance_Ohm))
        }
        foreach ($point in $points) {
            $px = & $mapX $point.Length_um
            $py = & $mapY $point.MeanResistance_Ohm
            $graphics.FillEllipse($brush, $px - 6, $py - 6, 12, 12)
            $graphics.DrawEllipse([System.Drawing.Pens]::White, $px - 6, $py - 6, 12, 12)
        }
        if ($ShowFits) {
            $fit = Get-LinearFit $points
            $graphics.DrawLine($fitPen, (& $mapX $xMin), (& $mapY ($fit.Intercept_Ohm + $fit.Slope_Ohm_per_um * $xMin)), (& $mapX $xMax), (& $mapY ($fit.Intercept_Ohm + $fit.Slope_Ohm_per_um * $xMax)))
        }
        $lx = $legendX + $legendOffset
        $graphics.DrawLine($pen, $lx, $legendY + 10, $lx + 32, $legendY + 10)
        $graphics.FillEllipse($brush, $lx + 12, $legendY + 4, 12, 12)
        $graphics.DrawString($series.Name, $fontLegend, $brushText, $lx + 40, $legendY - 2)
        $legendOffset += 250
        $pen.Dispose(); $fitPen.Dispose(); $brush.Dispose()
    }

    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose(); $bitmap.Dispose()
    $fontTitle.Dispose(); $fontSubtitle.Dispose(); $fontAxis.Dispose(); $fontTick.Dispose(); $fontLegend.Dispose()
    $brushText.Dispose(); $brushMuted.Dispose(); $gridPen.Dispose(); $axisPen.Dispose()
}

$palette = @('#2563EB', '#E11D48', '#059669', '#7C3AED', '#D97706')
$all001 = @()
$rows = @('1strow','2ndrow','3rdrow','4throw','5throw')
for ($i = 0; $i -lt $rows.Count; $i++) {
    $points = @($conditionSummary | Where-Object { $_.Row -eq $rows[$i] -and [Math]::Abs($_.Bias_V - 0.01) -lt 1e-9 })
    $all001 += [pscustomobject]@{ Name = $rows[$i]; Color = $palette[$i]; Points = $points }
}
$allValues = [double[]]@($all001 | ForEach-Object { $_.Points } | ForEach-Object { $_.MeanResistance_Ohm })
New-Plot -Path (Join-Path $OutputDir '01_all_rows_0p01V.png') -Title 'CTLM resistance by row at 0.01 V' -Subtitle 'Original 1strow only; each point is one spacing-level mean; dashed lines are linear fits' -Series $all001 -YMin ([Math]::Floor(($allValues | Measure-Object -Minimum).Minimum - 1)) -YMax ([Math]::Ceiling(($allValues | Measure-Object -Maximum).Maximum + 1))

$row3Series = @()
$biases = @(0.01, 0.05, 0.1)
for ($i = 0; $i -lt $biases.Count; $i++) {
    $bias = $biases[$i]
    $points = @($conditionSummary | Where-Object { $_.Row -eq '3rdrow' -and [Math]::Abs($_.Bias_V - $bias) -lt 1e-9 })
    $row3Series += [pscustomobject]@{ Name = ('{0:g} V' -f $bias); Color = $palette[$i]; Points = $points }
}
$row3Values = [double[]]@($row3Series | ForEach-Object { $_.Points } | ForEach-Object { $_.MeanResistance_Ohm })
New-Plot -Path (Join-Path $OutputDir '02_row3_bias_comparison.png') -Title 'Selected presentation data: 3rdrow bias comparison' -Subtitle 'All nine spacings retained; 3rdrow provides the strongest monotonic CTLM trend and paired bias comparison' -Series $row3Series -YMin ([Math]::Floor(($row3Values | Measure-Object -Minimum).Minimum - 1)) -YMax ([Math]::Ceiling(($row3Values | Measure-Object -Maximum).Maximum + 1))

$selectedPoints = @($conditionSummary | Where-Object { $_.Row -eq $best001.Row -and [Math]::Abs($_.Bias_V - 0.01) -lt 1e-9 })
$selectedFit = Get-LinearFit $selectedPoints
$selectedSeries = @([pscustomobject]@{ Name = $best001.Row; Color = '#2563EB'; Points = $selectedPoints })
$selectedValues = [double[]]@($selectedPoints | ForEach-Object { $_.MeanResistance_Ohm })
$subtitle = 'Best 0.01 V theory match: slope={0:F4} Ohm/um, intercept={1:F2} Ohm, R2={2:F4}, monotonic violations={3}' -f $selectedFit.Slope_Ohm_per_um, $selectedFit.Intercept_Ohm, $selectedFit.R2, $selectedFit.MonotonicViolations
New-Plot -Path (Join-Path $OutputDir '03_selected_0p01V_fit.png') -Title 'Presentation fit: resistance increases with CTLM gap' -Subtitle $subtitle -Series $selectedSeries -YMin ([Math]::Floor(($selectedValues | Measure-Object -Minimum).Minimum - 1)) -YMax ([Math]::Ceiling(($selectedValues | Measure-Object -Maximum).Maximum + 1))

$rank001 = @($regressionSummary | Where-Object { [Math]::Abs($_.Bias_V - 0.01) -lt 1e-9 } | Sort-Object TheoryMatchScore -Descending)
$notes = @()
$notes += '# W4 CTLM analysis'
$notes += ''
$notes += '## Processing decisions'
$notes += '- 1strow: original files only. All 1strow *_ver2.csv files are excluded.'
$notes += '- Each CSV is summarized first. Regression uses one equal-weight mean per row/bias/spacing condition, avoiding unequal raw sample counts.'
$notes += '- Both 5throw 10 um repeats are retained and averaged at the run-mean level.'
$notes += '- No spacing point was removed to improve linearity.'
$notes += ''
$notes += '## Presentation selection rule'
$notes += 'Positive slope is required. Candidates are ranked by R2 x positive adjacent-step fraction. This rewards linearity and monotonic resistance increase without cherry-picking individual spacings.'
$notes += ''
$notes += '| Rank | Row | Bias (V) | Slope (Ohm/um) | Intercept (Ohm) | R2 | Violations | Score |'
$notes += '|---:|---|---:|---:|---:|---:|---:|---:|'
$rank = 1
foreach ($item in $rank001) {
    $notes += ('| {0} | {1} | {2:F2} | {3:F4} | {4:F2} | {5:F4} | {6} | {7:F4} |' -f $rank, $item.Row, $item.Bias_V, $item.Slope_Ohm_per_um, $item.Intercept_Ohm, $item.R2, $item.MonotonicViolations, $item.TheoryMatchScore)
    $rank++
}
$notes += ''
$notes += '## Main conclusions for presentation'
$notes += ('1. At 0.01 V, {0} is the strongest complete-series match to the expected CTLM trend: resistance rises with spacing with R2={1:F4} and {2} monotonic violations.' -f $best001.Row, $best001.R2, $best001.MonotonicViolations)
$r001 = $regressionSummary | Where-Object { $_.Row -eq '3rdrow' -and [Math]::Abs($_.Bias_V - 0.01) -lt 1e-9 }
$r005 = $regressionSummary | Where-Object { $_.Row -eq '3rdrow' -and [Math]::Abs($_.Bias_V - 0.05) -lt 1e-9 }
$r010 = $regressionSummary | Where-Object { $_.Row -eq '3rdrow' -and [Math]::Abs($_.Bias_V - 0.1) -lt 1e-9 }
$notes += ('2. The same 3rdrow structure remains strongly linear at 0.05 V and 0.1 V (R2={0:F4}, {1:F4}), so the gap dependence is reproducible across bias.' -f $r005.R2, $r010.R2)
$notes += ('3. The fitted intercept changes from {0:F2} Ohm at 0.01 V to {1:F2} Ohm at 0.1 V. Ideal ohmic CTLM resistance should be nearly bias-independent, so this systematic shift should be presented as non-ideal bias dependence rather than hidden as measurement scatter.' -f $r001.Intercept_Ohm, $r010.Intercept_Ohm)
$notes += '4. These are spacing-domain linear fits for trend comparison. Final sheet resistance, transfer length, and specific contact resistivity require the handout CTLM geometry equation and device radii.'
$notes += ''
$notes += '## Output files'
$notes += '- file_summary.csv: one row per included measurement file'
$notes += '- condition_summary.csv: one row per row/bias/spacing condition'
$notes += '- regression_summary.csv: linear-fit and selection metrics'
$notes += '- presentation_selection.csv: selected row across available biases'
$notes += '- excluded_files.csv: exclusions and reasons'
$notes += '- PNG files: slide-ready plots at 1600 x 1000'
$notes -join "`r`n" | Set-Content -LiteralPath (Join-Path $OutputDir 'analysis_notes.md') -Encoding UTF8

Write-Output "Analysis complete: $OutputDir"
$regressionSummary | Format-Table Row, Bias_V, Slope_Ohm_per_um, Intercept_Ohm, R2, MonotonicViolations, TheoryMatchScore -AutoSize
