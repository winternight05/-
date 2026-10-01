# W4 CTLM analysis

## Processing decisions
- 1strow: original files only. All 1strow *_ver2.csv files are excluded.
- Each CSV is summarized first. Regression uses one equal-weight mean per row/bias/spacing condition, avoiding unequal raw sample counts.
- Both 5throw 10 um repeats are retained and averaged at the run-mean level.
- No spacing point was removed to improve linearity.
- CTLM geometry: inner radius ri=150 um and outer inner-edge radius ro=ri+gap.

## Presentation selection rule
Positive slope is required. Candidates are ranked by R2 x positive adjacent-step fraction. This rewards linearity and monotonic resistance increase without cherry-picking individual spacings.

| Rank | Row | Bias (V) | Slope (Ohm/um) | Intercept (Ohm) | R2 | Violations | Score |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | 3rdrow | 0.01 | 0.1594 | 77.11 | 0.8988 | 0 | 0.8969 |
| 2 | 2ndrow | 0.01 | 0.1400 | 76.76 | 0.8235 | 2 | 0.6214 |
| 3 | 1strow | 0.01 | 0.0850 | 77.40 | 0.8109 | 2 | 0.6071 |
| 4 | 5throw | 0.01 | 0.1908 | 77.69 | 0.7746 | 2 | 0.5816 |
| 5 | 4throw | 0.01 | 0.1026 | 79.32 | 0.7726 | 4 | 0.3865 |

## Main conclusions for presentation
1. At 0.01 V, 3rdrow is the strongest complete-series match to the expected CTLM trend: resistance rises with spacing with R2=0.8988 and 0 monotonic violations.
2. The same 3rdrow structure remains well described by the exact CTLM model at 0.05 V and 0.1 V (R2=0.9436, 0.9554), so the gap dependence is reproducible across bias.
3. The extrapolated R(d=0) changes from 76.90 Ohm at 0.01 V to 69.78 Ohm at 0.1 V. Ideal ohmic CTLM resistance should be nearly bias-independent, so this systematic shift should be presented as non-ideal bias dependence rather than hidden as measurement scatter.
4. Physical parameters use the exact two-contact CTLM model with modified Bessel functions, ri=150 um, and ro=ri+gap.
5. Selected 3rdrow at 0.01 V: Rsh=284.6 +/- 28.1 Ohm/sq, LT=102.93 +/- 8.00 um, rho_c=3.015E-002 +/- 5.550E-003 Ohm cm^2.
6. Model limitation: outer-contact width was not supplied. The exact two-contact model assumes a sufficiently wide outer contact and negligible metal sheet resistance.

## Output files
- file_summary.csv: one row per included measurement file
- condition_summary.csv: one row per row/bias/spacing condition
- regression_summary.csv: linear-fit and selection metrics
- ctlm_parameter_summary.csv: extracted Rsh, LT, rho_c, uncertainties, and CTLM fit quality
- presentation_selection.csv: selected row across available biases
- excluded_files.csv: exclusions and reasons
- PNG files: slide-ready trend, extraction, and bias-comparison plots
