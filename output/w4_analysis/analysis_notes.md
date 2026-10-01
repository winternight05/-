# W4 CTLM analysis

## Processing decisions
- 1strow: original files only. All 1strow *_ver2.csv files are excluded.
- Each CSV is summarized first. Regression uses one equal-weight mean per row/bias/spacing condition, avoiding unequal raw sample counts.
- Both 5throw 10 um repeats are retained and averaged at the run-mean level.
- No spacing point was removed to improve linearity.

## Presentation selection rule
Positive slope is required. Candidates are ranked by R2 x positive adjacent-step fraction. This rewards linearity and monotonic resistance increase without cherry-picking individual spacings.

| Rank | Row | Bias (V) | Slope (Ohm/um) | Intercept (Ohm) | R2 | Violations | Score |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | 3rdrow | 0.01 | 0.1594 | 77.11 | 0.8988 | 0 | 0.8988 |
| 2 | 2ndrow | 0.01 | 0.1400 | 76.76 | 0.8235 | 2 | 0.6176 |
| 3 | 1strow | 0.01 | 0.0850 | 77.40 | 0.8109 | 2 | 0.6082 |
| 4 | 5throw | 0.01 | 0.1908 | 77.69 | 0.7746 | 2 | 0.5809 |
| 5 | 4throw | 0.01 | 0.1026 | 79.32 | 0.7726 | 4 | 0.3863 |

## Main conclusions for presentation
1. At 0.01 V, 3rdrow is the strongest complete-series match to the expected CTLM trend: resistance rises with spacing with R2=0.8988 and 0 monotonic violations.
2. The same 3rdrow structure remains strongly linear at 0.05 V and 0.1 V (R2=0.9472, 0.9578), so the gap dependence is reproducible across bias.
3. The fitted intercept changes from 77.11 Ohm at 0.01 V to 70.02 Ohm at 0.1 V. Ideal ohmic CTLM resistance should be nearly bias-independent, so this systematic shift should be presented as non-ideal bias dependence rather than hidden as measurement scatter.
4. These are spacing-domain linear fits for trend comparison. Final sheet resistance, transfer length, and specific contact resistivity require the handout CTLM geometry equation and device radii.

## Output files
- file_summary.csv: one row per included measurement file
- condition_summary.csv: one row per row/bias/spacing condition
- regression_summary.csv: linear-fit and selection metrics
- presentation_selection.csv: selected row across available biases
- excluded_files.csv: exclusions and reasons
- PNG files: slide-ready plots at 1600 x 1000
