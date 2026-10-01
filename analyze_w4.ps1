param(
    [string]$InputDir = (Join-Path $PSScriptRoot 'w4_data'),
    [string]$OutputDir = (Join-Path $PSScriptRoot 'output\w4_analysis'),
    [double]$InnerRadius_um = 150.0
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

function Get-I0([double]$x) {
    $ax=[Math]::Abs($x)
    if($ax -lt 3.75){$y=($x/3.75)*($x/3.75);return 1+$y*(3.5156229+$y*(3.0899424+$y*(1.2067492+$y*(0.2659732+$y*(0.0360768+$y*0.0045813)))))}
    $y=3.75/$ax;return ([Math]::Exp($ax)/[Math]::Sqrt($ax))*(0.39894228+$y*(0.01328592+$y*(0.00225319+$y*(-0.00157565+$y*(0.00916281+$y*(-0.02057706+$y*(0.02635537+$y*(-0.01647633+$y*0.00392377))))))))
}
function Get-I1([double]$x) {
    $ax=[Math]::Abs($x)
    if($ax -lt 3.75){$y=($x/3.75)*($x/3.75);return $x*(0.5+$y*(0.87890594+$y*(0.51498869+$y*(0.15084934+$y*(0.02658733+$y*(0.00301532+$y*0.00032411))))))}
    $y=3.75/$ax;$ans=([Math]::Exp($ax)/[Math]::Sqrt($ax))*(0.39894228+$y*(-0.03988024+$y*(-0.00362018+$y*(0.00163801+$y*(-0.01031555+$y*(0.02282967+$y*(-0.02895312+$y*(0.01787654-$y*0.00420059))))))));return $(if($x-lt 0){-$ans}else{$ans})
}
function Get-K0([double]$x) {
    if($x -le 0){throw 'K0 requires x > 0'}
    if($x -le 2){$y=$x*$x/4;return -[Math]::Log($x/2)*(Get-I0 $x)+(-0.57721566+$y*(0.42278420+$y*(0.23069756+$y*(0.03488590+$y*(0.00262698+$y*(0.00010750+$y*0.00000740))))))}
    $y=2/$x;return ([Math]::Exp(-$x)/[Math]::Sqrt($x))*(1.25331414+$y*(-0.07832358+$y*(0.02189568+$y*(-0.01062446+$y*(0.00587872+$y*(-0.00251540+$y*0.00053208))))))
}
function Get-K1([double]$x) {
    if($x -le 0){throw 'K1 requires x > 0'}
    if($x -le 2){$y=$x*$x/4;return [Math]::Log($x/2)*(Get-I1 $x)+(1/$x)*(1+$y*(0.15443144+$y*(-0.67278579+$y*(-0.18156897+$y*(-0.01919402+$y*(-0.00110404+$y*(-0.00004686)))))))}
    $y=2/$x;return ([Math]::Exp(-$x)/[Math]::Sqrt($x))*(1.25331414+$y*(0.23498619+$y*(-0.03655620+$y*(0.01504268+$y*(-0.00780353+$y*(0.00325614+$y*(-0.00068245)))))))
}
function Get-CtlmFactor([double]$Gap,[double]$InnerRadius,[double]$Lt) {
    $ro=$InnerRadius+$Gap;$xi=$InnerRadius/$Lt;$xo=$ro/$Lt
    if($xi -gt 50){$innerRatio=1+1/(2*$xi)+3/(8*$xi*$xi)}else{$innerRatio=(Get-I0 $xi)/(Get-I1 $xi)}
    if($xo -gt 50){$outerRatio=1-1/(2*$xo)+3/(8*$xo*$xo)}else{$outerRatio=(Get-K0 $xo)/(Get-K1 $xo)}
    return ([Math]::Log($ro/$InnerRadius)+($Lt/$InnerRadius)*$innerRatio+($Lt/$ro)*$outerRatio)/(2*[Math]::PI)
}
function Get-CtlmTrial($Points,[double]$InnerRadius,[double]$Lt) {
    $sumFY=0.;$sumFF=0.;foreach($p in $Points){$f=Get-CtlmFactor ([double]$p.Length_um) $InnerRadius $Lt;$sumFY+=$f*[double]$p.MeanResistance_Ohm;$sumFF+=$f*$f};$rsh=$sumFY/$sumFF;$sse=0.;foreach($p in $Points){$f=Get-CtlmFactor ([double]$p.Length_um) $InnerRadius $Lt;$e=[double]$p.MeanResistance_Ohm-$rsh*$f;$sse+=$e*$e};return [pscustomobject]@{Lt=$Lt;Rsh=$rsh;SSE=$sse}
}
function Get-CtlmFit($Points,[double]$InnerRadius) {
    # Exact two-contact CTLM model using modified Bessel functions.
    $lo=[Math]::Log(0.1);$hi=[Math]::Log(10000.0);$phi=([Math]::Sqrt(5)-1)/2;$c=$hi-$phi*($hi-$lo);$d=$lo+$phi*($hi-$lo);$fc=Get-CtlmTrial $Points $InnerRadius ([Math]::Exp($c));$fd=Get-CtlmTrial $Points $InnerRadius ([Math]::Exp($d))
    for($iter=0;$iter -lt 120;$iter++){if($fc.SSE -lt $fd.SSE){$hi=$d;$d=$c;$fd=$fc;$c=$hi-$phi*($hi-$lo);$fc=Get-CtlmTrial $Points $InnerRadius ([Math]::Exp($c))}else{$lo=$c;$c=$d;$fc=$fd;$d=$lo+$phi*($hi-$lo);$fd=Get-CtlmTrial $Points $InnerRadius ([Math]::Exp($d))}}
    $best=Get-CtlmTrial $Points $InnerRadius ([Math]::Exp(($lo+$hi)/2));$lt=$best.Lt;$rsh=$best.Rsh;$rho=$rsh*[Math]::Pow($lt*1e-4,2);$meanY=Get-Mean ([double[]]@($Points|ForEach-Object{[double]$_.MeanResistance_Ohm}));$sst=0.;foreach($p in $Points){$dy=[double]$p.MeanResistance_Ohm-$meanY;$sst+=$dy*$dy};$dof=[Math]::Max(1,$Points.Count-2);$sigma2=$best.SSE/$dof
    $j11=0.;$j22=0.;$j12=0.;$h=[Math]::Max($lt*1e-4,1e-5);foreach($p in $Points){$gap=[double]$p.Length_um;$j1=Get-CtlmFactor $gap $InnerRadius $lt;$j2=$rsh*((Get-CtlmFactor $gap $InnerRadius ($lt+$h))-(Get-CtlmFactor $gap $InnerRadius ($lt-$h)))/(2*$h);$j11+=$j1*$j1;$j22+=$j2*$j2;$j12+=$j1*$j2};$det=$j11*$j22-$j12*$j12;$varR=$sigma2*$j22/$det;$varL=$sigma2*$j11/$det;$covRL=-$sigma2*$j12/$det;$rshSe=[Math]::Sqrt([Math]::Max(0,$varR));$ltSe=[Math]::Sqrt([Math]::Max(0,$varL));$dr=$lt*$lt*1e-8;$dl=2*$rsh*$lt*1e-8;$varRho=$dr*$dr*$varR+$dl*$dl*$varL+2*$dr*$dl*$covRL;$rhoSe=[Math]::Sqrt([Math]::Max(0,$varRho));$r0=$rsh*(Get-CtlmFactor 0 $InnerRadius $lt)
    # Use conservative independent-error propagation for rho_c because Rsh and LT are strongly correlated.
    $rhoSe=[Math]::Sqrt([Math]::Pow($lt*$lt*1e-8*$rshSe,2)+[Math]::Pow(2*$rsh*$lt*1e-8*$ltSe,2))
    return [pscustomobject]@{Rsh_Ohm_per_sq=$rsh;Rsh_SE=$rshSe;Lt_um=$lt;Lt_SE=$ltSe;RhoC_Ohm_cm2=$rho;RhoC_SE=$rhoSe;ContactTermAtZeroGap_Ohm=$r0;R2=if($sst-gt 0){1-$best.SSE/$sst}else{1};RMSE_Ohm=[Math]::Sqrt($sigma2)}
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
    $ctlm = Get-CtlmFit $points $InnerRadius_um
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
        TheoryMatchScore = $ctlm.R2 * $fit.PositiveStepFraction
        InnerRadius_um = $InnerRadius_um
        Rsh_Ohm_per_sq = $ctlm.Rsh_Ohm_per_sq
        Rsh_SE = $ctlm.Rsh_SE
        Lt_um = $ctlm.Lt_um
        Lt_SE = $ctlm.Lt_SE
        RhoC_Ohm_cm2 = $ctlm.RhoC_Ohm_cm2
        RhoC_SE = $ctlm.RhoC_SE
        ContactTermAtZeroGap_Ohm = $ctlm.ContactTermAtZeroGap_Ohm
        CTLM_R2 = $ctlm.R2
        CTLM_RMSE_Ohm = $ctlm.RMSE_Ohm
        CTLM_Model = 'Exact modified-Bessel two-contact model'
    }
}
$regressionSummary = @($regressionSummary | Sort-Object Bias_V, @{Expression='TheoryMatchScore';Descending=$true})

$best001 = $regressionSummary | Where-Object { [Math]::Abs($_.Bias_V - 0.01) -lt 1e-9 -and $_.Slope_Ohm_per_um -gt 0 } | Sort-Object TheoryMatchScore -Descending | Select-Object -First 1
$selected = @($regressionSummary | Where-Object { $_.Row -eq $best001.Row })

$fileSummary | Export-Csv -LiteralPath (Join-Path $OutputDir 'file_summary.csv') -NoTypeInformation -Encoding UTF8
$conditionSummary | Export-Csv -LiteralPath (Join-Path $OutputDir 'condition_summary.csv') -NoTypeInformation -Encoding UTF8
$regressionSummary | Export-Csv -LiteralPath (Join-Path $OutputDir 'regression_summary.csv') -NoTypeInformation -Encoding UTF8
$regressionSummary | Select-Object Row,Bias_V,CTLM_Model,InnerRadius_um,Rsh_Ohm_per_sq,Rsh_SE,Lt_um,Lt_SE,RhoC_Ohm_cm2,RhoC_SE,ContactTermAtZeroGap_Ohm,CTLM_R2,CTLM_RMSE_Ohm | Export-Csv -LiteralPath (Join-Path $OutputDir 'ctlm_parameter_summary.csv') -NoTypeInformation -Encoding UTF8
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

function New-CtlmExtractionPlot {
    param([string]$Path, $Points, $Fit, [double]$InnerRadius, [string]$SeriesName)
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
    $fontNote = New-Object System.Drawing.Font('Arial', 13, [System.Drawing.FontStyle]::Bold)
    $text = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(35,42,52))
    $muted = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(90,99,110))
    $blue = [System.Drawing.ColorTranslator]::FromHtml('#2563EB')
    $blueBrush = New-Object System.Drawing.SolidBrush($blue)
    $dataPen = New-Object System.Drawing.Pen($blue,3)
    $fitPen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml('#E11D48'),3)
    $fitPen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
    $gridPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(225,229,235),1)
    $axisPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(55,65,81),2)
    $noteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(245,248,252))

    $ordered = @($Points | Sort-Object Length_um)
    $ys = [double[]]@($ordered | ForEach-Object {[double]$_.MeanResistance_Ohm})
    $xMin = 0.0; $xMax = 50.0
    $allY = @($ys) + @([double]$Fit.ContactTermAtZeroGap_Ohm)
    $yMin = [Math]::Floor((($allY|Measure-Object -Minimum).Minimum - 1))
    $yMax = [Math]::Ceiling((($allY|Measure-Object -Maximum).Maximum + 1))
    $left=145; $top=150; $plotWidth=1310; $plotHeight=675
    $mapX={param([double]$x) $left+(($x-$xMin)/($xMax-$xMin))*$plotWidth}
    $mapY={param([double]$y) $top+$plotHeight-(($y-$yMin)/($yMax-$yMin))*$plotHeight}

    $graphics.DrawString('Exact CTLM parameter extraction: '+$SeriesName,$fontTitle,$text,65,28)
    $graphics.DrawString('Modified-Bessel CTLM fit; ri=150 um, ro=ri+gap; d=0 value is model extrapolation',$fontSubtitle,$muted,68,80)
    for($i=0;$i -le 5;$i++){
        $xv=$xMin+($xMax-$xMin)*$i/5.0; $px=&$mapX $xv
        $graphics.DrawLine($gridPen,$px,$top,$px,$top+$plotHeight)
        $lab=('{0:F0}' -f $xv);$sz=$graphics.MeasureString($lab,$fontTick);$graphics.DrawString($lab,$fontTick,$muted,$px-$sz.Width/2,$top+$plotHeight+12)
        $yv=$yMin+($yMax-$yMin)*$i/5.0; $py=&$mapY $yv
        $graphics.DrawLine($gridPen,$left,$py,$left+$plotWidth,$py)
        $lab=('{0:F0}' -f $yv);$sz=$graphics.MeasureString($lab,$fontTick);$graphics.DrawString($lab,$fontTick,$muted,$left-$sz.Width-14,$py-$sz.Height/2)
    }
    $graphics.DrawLine($axisPen,$left,$top,$left,$top+$plotHeight)
    $graphics.DrawLine($axisPen,$left,$top+$plotHeight,$left+$plotWidth,$top+$plotHeight)
    for($i=1;$i -lt $ordered.Count;$i++){$graphics.DrawLine($dataPen,(&$mapX ([double]$ordered[$i-1].Length_um)),(&$mapY ([double]$ordered[$i-1].MeanResistance_Ohm)),(&$mapX ([double]$ordered[$i].Length_um)),(&$mapY ([double]$ordered[$i].MeanResistance_Ohm)))}
    foreach($p in $ordered){$px=&$mapX ([double]$p.Length_um);$py=&$mapY ([double]$p.MeanResistance_Ohm);$graphics.FillEllipse($blueBrush,$px-6,$py-6,12,12)}
    $lastX=0.;$lastY=$Fit.Rsh_Ohm_per_sq*(Get-CtlmFactor 0 $InnerRadius $Fit.Lt_um)
    for($gap=0.5;$gap -le 50.0001;$gap+=0.5){$pred=$Fit.Rsh_Ohm_per_sq*(Get-CtlmFactor $gap $InnerRadius $Fit.Lt_um);$graphics.DrawLine($fitPen,(&$mapX $lastX),(&$mapY $lastY),(&$mapX $gap),(&$mapY $pred));$lastX=$gap;$lastY=$pred}
    $xLabel='CTLM gap spacing (um)';$sz=$graphics.MeasureString($xLabel,$fontAxis);$graphics.DrawString($xLabel,$fontAxis,$text,$left+($plotWidth-$sz.Width)/2,$top+$plotHeight+55)
    $graphics.TranslateTransform(35,$top+$plotHeight/2);$graphics.RotateTransform(-90);$yLabel='Mean resistance (Ohm)';$sz=$graphics.MeasureString($yLabel,$fontAxis);$graphics.DrawString($yLabel,$fontAxis,$text,-$sz.Width/2,0);$graphics.ResetTransform()
    $graphics.FillRectangle($noteBrush,$left+25,$top+22,570,165)
    $note=@(
        ('Rsh = {0:F1} +/- {1:F1} Ohm/sq' -f $Fit.Rsh_Ohm_per_sq,$Fit.Rsh_SE),
        ('LT = {0:F2} +/- {1:F2} um' -f $Fit.Lt_um,$Fit.Lt_SE),
        ('rho_c = {0:E3} +/- {1:E3} Ohm cm^2' -f $Fit.RhoC_Ohm_cm2,$Fit.RhoC_SE),
        ('R(d=0) = {0:F2} Ohm (extrapolated)' -f $Fit.ContactTermAtZeroGap_Ohm),
        ('R2 in resistance domain = {0:F4}' -f $Fit.R2)
    )
    for($i=0;$i -lt $note.Count;$i++){$graphics.DrawString($note[$i],$fontNote,$text,$left+42,$top+36+$i*29)}
    $bitmap.Save($Path,[System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose();$bitmap.Dispose();$fontTitle.Dispose();$fontSubtitle.Dispose();$fontAxis.Dispose();$fontTick.Dispose();$fontNote.Dispose();$text.Dispose();$muted.Dispose();$blueBrush.Dispose();$dataPen.Dispose();$fitPen.Dispose();$gridPen.Dispose();$axisPen.Dispose();$noteBrush.Dispose()
}

function New-ParameterComparisonPlot {
    param([string]$Path, $Rows)
    $width=1600;$height=900;$bitmap=New-Object System.Drawing.Bitmap($width,$height);$g=[System.Drawing.Graphics]::FromImage($bitmap);$g.SmoothingMode=[System.Drawing.Drawing2D.SmoothingMode]::AntiAlias;$g.Clear([System.Drawing.Color]::White)
    $titleFont=New-Object System.Drawing.Font('Arial',28,[System.Drawing.FontStyle]::Bold);$axisFont=New-Object System.Drawing.Font('Arial',13);$tickFont=New-Object System.Drawing.Font('Arial',12);$text=New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(35,42,52));$muted=New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(90,99,110));$blue=[System.Drawing.ColorTranslator]::FromHtml('#2563EB');$pen=New-Object System.Drawing.Pen($blue,3);$brush=New-Object System.Drawing.SolidBrush($blue);$grid=New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(225,229,235),1);$axis=New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(55,65,81),2)
    $g.DrawString('3rdrow extracted CTLM parameters by bias',$titleFont,$text,65,30)
    $panels=@(
        [pscustomobject]@{Title='Sheet resistance';Field='Rsh_Ohm_per_sq';SE='Rsh_SE';Unit='Ohm/sq';Scale=1.0},
        [pscustomobject]@{Title='Transfer length';Field='Lt_um';SE='Lt_SE';Unit='um';Scale=1.0},
        [pscustomobject]@{Title='Specific contact resistivity';Field='RhoC_Ohm_cm2';SE='RhoC_SE';Unit='Ohm cm^2';Scale=1000.0}
    )
    for($panelIndex=0;$panelIndex -lt 3;$panelIndex++){
        $p=$panels[$panelIndex];$left=85+$panelIndex*510;$top=150;$pw=430;$ph=570
        $vals=[double[]]@($Rows|ForEach-Object{[double]($_.$($p.Field))*$p.Scale});$ses=[double[]]@($Rows|ForEach-Object{[double]($_.$($p.SE))*$p.Scale});$low=@();$high=@();for($i=0;$i -lt $vals.Count;$i++){$low+=$vals[$i]-$ses[$i];$high+=$vals[$i]+$ses[$i]};$ymin=($low|Measure-Object -Minimum).Minimum;$ymax=($high|Measure-Object -Maximum).Maximum;$pad=[Math]::Max(($ymax-$ymin)*0.25,[Math]::Abs($ymax)*0.03);$ymin-=$pad;$ymax+=$pad;$mapY={param([double]$y) $top+$ph-(($y-$ymin)/($ymax-$ymin))*$ph}
        $g.DrawString($p.Title,$axisFont,$text,$left,$top-45)
        for($j=0;$j -le 4;$j++){$yv=$ymin+($ymax-$ymin)*$j/4.;$py=&$mapY $yv;$g.DrawLine($grid,$left,$py,$left+$pw,$py);$fmt=if($panelIndex -eq 2){'{0:F1}'}else{'{0:F0}'};$lab=$fmt -f $yv;$sz=$g.MeasureString($lab,$tickFont);$g.DrawString($lab,$tickFont,$muted,$left-$sz.Width-10,$py-$sz.Height/2)}
        $g.DrawLine($axis,$left,$top,$left,$top+$ph);$g.DrawLine($axis,$left,$top+$ph,$left+$pw,$top+$ph)
        $prev=$null
        for($i=0;$i -lt $Rows.Count;$i++){$px=$left+70+$i*145;$py=&$mapY $vals[$i];$errPx=[Math]::Abs((&$mapY ($vals[$i]+$ses[$i]))-$py);$g.DrawLine($pen,$px,$py-$errPx,$px,$py+$errPx);$g.DrawLine($pen,$px-7,$py-$errPx,$px+7,$py-$errPx);$g.DrawLine($pen,$px-7,$py+$errPx,$px+7,$py+$errPx);if($null-ne$prev){$g.DrawLine($pen,$prev.X,$prev.Y,$px,$py)};$g.FillEllipse($brush,$px-7,$py-7,14,14);$lab=('{0:g} V' -f [double]$Rows[$i].Bias_V);$sz=$g.MeasureString($lab,$tickFont);$g.DrawString($lab,$tickFont,$muted,$px-$sz.Width/2,$top+$ph+15);$prev=[pscustomobject]@{X=$px;Y=$py}}
        $unit=if($panelIndex -eq 2){'mOhm cm^2'}else{$p.Unit};$sz=$g.MeasureString($unit,$axisFont);$g.DrawString($unit,$axisFont,$text,$left+($pw-$sz.Width)/2,$top+$ph+60)
    }
    $g.DrawString('Error bars: one standard error; rho_c uses conservative independent-error propagation',$axisFont,$muted,65,835)
    $bitmap.Save($Path,[System.Drawing.Imaging.ImageFormat]::Png);$g.Dispose();$bitmap.Dispose();$titleFont.Dispose();$axisFont.Dispose();$tickFont.Dispose();$text.Dispose();$muted.Dispose();$pen.Dispose();$brush.Dispose();$grid.Dispose();$axis.Dispose()
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

$selectedCtlm = Get-CtlmFit $selectedPoints $InnerRadius_um
New-CtlmExtractionPlot -Path (Join-Path $OutputDir '04_selected_ctlm_extraction.png') -Points $selectedPoints -Fit $selectedCtlm -InnerRadius $InnerRadius_um -SeriesName ($best001.Row + ' at 0.01 V')
$row3Parameters = @($regressionSummary | Where-Object { $_.Row -eq '3rdrow' } | Sort-Object Bias_V)
New-ParameterComparisonPlot -Path (Join-Path $OutputDir '05_row3_ctlm_parameters_by_bias.png') -Rows $row3Parameters

$rank001 = @($regressionSummary | Where-Object { [Math]::Abs($_.Bias_V - 0.01) -lt 1e-9 } | Sort-Object TheoryMatchScore -Descending)
$notes = @()
$notes += '# W4 CTLM analysis'
$notes += ''
$notes += '## Processing decisions'
$notes += '- 1strow: original files only. All 1strow *_ver2.csv files are excluded.'
$notes += '- Each CSV is summarized first. Regression uses one equal-weight mean per row/bias/spacing condition, avoiding unequal raw sample counts.'
$notes += '- Both 5throw 10 um repeats are retained and averaged at the run-mean level.'
$notes += '- No spacing point was removed to improve linearity.'
$notes += ('- CTLM geometry: inner radius ri={0:g} um and outer inner-edge radius ro=ri+gap.' -f $InnerRadius_um)
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
$notes += ('2. The same 3rdrow structure remains well described by the exact CTLM model at 0.05 V and 0.1 V (R2={0:F4}, {1:F4}), so the gap dependence is reproducible across bias.' -f $r005.CTLM_R2, $r010.CTLM_R2)
$notes += ('3. The extrapolated R(d=0) changes from {0:F2} Ohm at 0.01 V to {1:F2} Ohm at 0.1 V. Ideal ohmic CTLM resistance should be nearly bias-independent, so this systematic shift should be presented as non-ideal bias dependence rather than hidden as measurement scatter.' -f $r001.ContactTermAtZeroGap_Ohm, $r010.ContactTermAtZeroGap_Ohm)
$notes += '4. These are spacing-domain linear fits for trend comparison. Final sheet resistance, transfer length, and specific contact resistivity require the handout CTLM geometry equation and device radii.'
$notes[($notes.Count-1)] = '4. Physical parameters use the exact two-contact CTLM model with modified Bessel functions, ri=150 um, and ro=ri+gap.'
$notes += ('5. Selected 3rdrow at 0.01 V: Rsh={0:F1} +/- {1:F1} Ohm/sq, LT={2:F2} +/- {3:F2} um, rho_c={4:E3} +/- {5:E3} Ohm cm^2.' -f $selectedCtlm.Rsh_Ohm_per_sq,$selectedCtlm.Rsh_SE,$selectedCtlm.Lt_um,$selectedCtlm.Lt_SE,$selectedCtlm.RhoC_Ohm_cm2,$selectedCtlm.RhoC_SE)
$notes += '6. Model limitation: outer-contact width was not supplied. The exact two-contact model assumes a sufficiently wide outer contact and negligible metal sheet resistance.'
$notes += ''
$notes += '## Output files'
$notes += '- file_summary.csv: one row per included measurement file'
$notes += '- condition_summary.csv: one row per row/bias/spacing condition'
$notes += '- regression_summary.csv: linear-fit and selection metrics'
$notes += '- ctlm_parameter_summary.csv: extracted Rsh, LT, rho_c, uncertainties, and CTLM fit quality'
$notes += '- presentation_selection.csv: selected row across available biases'
$notes += '- excluded_files.csv: exclusions and reasons'
$notes += '- PNG files: slide-ready trend, extraction, and bias-comparison plots'
$notes -join "`r`n" | Set-Content -LiteralPath (Join-Path $OutputDir 'analysis_notes.md') -Encoding UTF8

Write-Output "Analysis complete: $OutputDir"
$regressionSummary | Format-Table Row, Bias_V, Rsh_Ohm_per_sq, Lt_um, RhoC_Ohm_cm2, CTLM_R2, MonotonicViolations, TheoryMatchScore -AutoSize
