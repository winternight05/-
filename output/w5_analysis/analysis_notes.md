# W5 Pt/n-Si Schottky analysis

## Processing decisions

- The presentation I-V range is limited to the common -1 V to +1 V interval, as requested. Raw CSV files are unchanged.
- Current offset is the interpolated current at 0 V. Corrected current is `I_raw - I(0)`.
- `1_30um.csv` contains a restarted sweep; only its longest monotonic segment is used.
- Incomplete positive sweeps are retained because every file covers the common -1 V to +1 V interval.
- File gap values are treated as device/site labels, not CTLM transport lengths. The handout specifies a vertical Pt-electrode-to-stage Schottky measurement.
- C-V nonnumeric `O/R` rows are excluded. The fit uses numeric points with V <= 0 V and D <= 0.1.

## Constants and equations

- Circular Pt electrode radius: 150 um; area = 7.068583e-04 cm^2
- Temperature: 300 K; silicon relative permittivity: 11.7; Nc = 2.800e+19 cm^-3
- `1/C^2 = 2(Vbi-V)/(q eps_Si ND A^2)`
- `ND = -2/(q eps_Si A^2 slope)`
- `Vbi = -intercept/slope`
- `phi_n = (kT/q) ln(Nc/ND)` and `phi_B = Vbi + phi_n`

## Main results

- Best Schottky-like I-V by the predefined score: **3_20um.csv**, RR(+/-1 V)=1.58e+05, forward ln(I)-V R2=0.98882, n=1.322.
- Most Ohmic-like measurement: **1_35um.csv**. This is a relative label and does not imply an ideal Ohmic contact.
- Mean Vbi = 0.7192 +/- 0.0228 V.
- Mean ND = 1.1705e+15 +/- 2.2638e+13 cm^-3.
- Mean phi_B(C-V) = 0.9798 +/- 0.0224 eV.

## Interpretation limits

- I-V thermionic-emission values are diagnostic because series resistance, barrier inhomogeneity and current-offset artifacts can distort the fitted ideality factor and I-V barrier height.
- The C-V extraction follows the course handout and is the primary quantitative result.
