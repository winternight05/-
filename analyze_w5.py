#!/usr/bin/env python3
"""Analyze W5 Pt/n-Si Schottky I-V and C-V measurements.

The presentation I-V range is intentionally limited to the common -1 V to +1 V
window.  Raw files are never modified.  C-V parameters follow the equations in
the Week 4-6 MS Junction Diode handout.
"""

from __future__ import annotations

import argparse
import csv
import math
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont


Q = 1.602176634e-19
KB_EV = 8.617333262e-5
EPS0_F_PER_CM = 8.8541878128e-14
EPS_SI_REL = 11.7
NC_SI_CM3 = 2.8e19
RICHARDSON_NSI = 112.0


def read_csv(path: Path):
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def write_csv(path: Path, rows: list[dict], fields: list[str] | None = None):
    path.parent.mkdir(parents=True, exist_ok=True)
    if fields is None:
        fields = list(rows[0].keys()) if rows else []
    with path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def as_float(value):
    try:
        return float(str(value).strip())
    except (TypeError, ValueError):
        return None


def linear_fit(x, y):
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)
    n = len(x)
    if n < 3 or np.ptp(x) == 0:
        return None
    design = np.column_stack([x, np.ones(n)])
    coef, _, _, _ = np.linalg.lstsq(design, y, rcond=None)
    slope, intercept = map(float, coef)
    pred = slope * x + intercept
    resid = y - pred
    sse = float(np.sum(resid**2))
    sst = float(np.sum((y - np.mean(y)) ** 2))
    r2 = 1.0 - sse / sst if sst > 0 else 1.0
    sigma2 = sse / max(1, n - 2)
    cov = sigma2 * np.linalg.inv(design.T @ design)
    return {
        "slope": slope,
        "intercept": intercept,
        "r2": r2,
        "rmse": math.sqrt(sigma2),
        "slope_se": math.sqrt(max(0.0, float(cov[0, 0]))),
        "intercept_se": math.sqrt(max(0.0, float(cov[1, 1]))),
        "cov_slope_intercept": float(cov[0, 1]),
        "pred": pred,
    }


def interp(x, y, target):
    order = np.argsort(x)
    return float(np.interp(target, np.asarray(x)[order], np.asarray(y)[order]))


def longest_monotonic_segment(v):
    starts = [0]
    for i in range(1, len(v)):
        if v[i] < v[i - 1] - 1e-5:
            starts.append(i)
    starts.append(len(v))
    segments = [(starts[i], starts[i + 1]) for i in range(len(starts) - 1)]
    return max(segments, key=lambda p: p[1] - p[0]), len(segments)


def forward_log_fit(v, icorr, temperature):
    vt = KB_EV * temperature
    candidates = []
    starts = np.arange(0.10, 0.31, 0.02)
    ends = np.arange(0.35, 0.71, 0.02)
    for lo in starts:
        for hi in ends:
            if hi - lo < 0.16:
                continue
            mask = (v >= lo - 1e-9) & (v <= hi + 1e-9) & (icorr > 0)
            if int(np.sum(mask)) < 15:
                continue
            fit = linear_fit(v[mask], np.log(icorr[mask]))
            if not fit or fit["slope"] <= 0:
                continue
            ideality = 1.0 / (vt * fit["slope"])
            if 0.6 <= ideality <= 12.0:
                score = fit["r2"] - 0.0005 * (hi - lo < 0.22)
                candidates.append((score, lo, hi, ideality, fit))
    if not candidates:
        return None
    _, lo, hi, ideality, fit = max(candidates, key=lambda t: (t[0], t[2] - t[1]))
    return lo, hi, ideality, fit


def get_font(size, bold=False):
    candidates = [
        Path("C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf"),
        Path("C:/Windows/Fonts/calibrib.ttf" if bold else "C:/Windows/Fonts/calibri.ttf"),
    ]
    for path in candidates:
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


NAVY = "#17365D"
BLUE = "#2F6BFF"
RED = "#EF476F"
GREEN = "#06A77D"
ORANGE = "#F59E0B"
PURPLE = "#8B5CF6"
GRAY = "#6B7280"
LIGHT = "#E5E7EB"
COLORS = [BLUE, RED, GREEN, PURPLE, ORANGE, "#00A6A6"]


class Plot:
    def __init__(self, width=1600, height=1000, title="", subtitle=""):
        self.image = Image.new("RGB", (width, height), "white")
        self.draw = ImageDraw.Draw(self.image)
        self.w, self.h = width, height
        self.title = title
        self.subtitle = subtitle

    def save(self, path):
        self.image.save(path, dpi=(180, 180))

    def panel(self, box, series, xlabel, ylabel, title, xlim=None, ylim=None, legend=True,
              scatter=False, log_y=False):
        x0, y0, x1, y1 = box
        lm, rm, tm, bm = 95, 25, 55, 75
        px0, py0, px1, py1 = x0 + lm, y0 + tm, x1 - rm, y1 - bm
        xs = [float(x) for s in series for x in s[1]]
        ys = [float(y) for s in series for y in s[2] if math.isfinite(float(y))]
        if log_y:
            ys = [math.log10(max(abs(y), 1e-30)) for y in ys]
        xmin, xmax = xlim or (min(xs), max(xs))
        ymin, ymax = ylim or (min(ys), max(ys))
        if xmax == xmin:
            xmax += 1
        if ymax == ymin:
            ymax += 1
        ypad = 0.06 * (ymax - ymin)
        ymin, ymax = ymin - ypad, ymax + ypad

        def sx(x): return px0 + (x - xmin) / (xmax - xmin) * (px1 - px0)
        def sy(y):
            yy = math.log10(max(abs(y), 1e-30)) if log_y else y
            return py1 - (yy - ymin) / (ymax - ymin) * (py1 - py0)

        self.draw.rectangle((px0, py0, px1, py1), outline="#9CA3AF", width=2)
        for k in range(6):
            xx = xmin + k * (xmax - xmin) / 5
            xp = sx(xx)
            self.draw.line((xp, py0, xp, py1), fill=LIGHT, width=1)
            txt = f"{xx:.2g}"
            self.draw.text((xp - 18, py1 + 10), txt, fill="#374151", font=get_font(18))
        for k in range(6):
            yy = ymin + k * (ymax - ymin) / 5
            yp = py1 - k * (py1 - py0) / 5
            self.draw.line((px0, yp, px1, yp), fill=LIGHT, width=1)
            txt = f"{yy:.2f}" if log_y else f"{yy:.3g}"
            self.draw.text((x0 + 4, yp - 10), txt, fill="#374151", font=get_font(18))
        self.draw.text((x0 + 10, y0 + 8), title, fill=NAVY, font=get_font(25, True))
        self.draw.text(((px0 + px1) // 2 - 50, y1 - 42), xlabel, fill="#111827", font=get_font(20))
        self.draw.text((px0, y0 + 34), ylabel, fill="#111827", font=get_font(18))

        for idx, entry in enumerate(series):
            name, xvals, yvals, color = entry[:4]
            draw_points = entry[4] if len(entry) > 4 else scatter
            line_width = entry[5] if len(entry) > 5 else 4
            points = []
            for x, y in zip(xvals, yvals):
                if math.isfinite(float(y)):
                    points.append((sx(float(x)), sy(float(y))))
            if len(points) >= 2 and line_width > 0:
                self.draw.line(points, fill=color, width=line_width)
            if draw_points:
                for xp, yp in points:
                    self.draw.ellipse((xp - 2, yp - 2, xp + 2, yp + 2), fill=color)
            if legend:
                lx = px0 + 15 + (idx % 3) * 400
                ly = py0 + 12 + (idx // 3) * 28
                self.draw.line((lx, ly + 8, lx + 34, ly + 8), fill=color, width=4)
                self.draw.text((lx + 42, ly - 4), name, fill="#111827", font=get_font(17))


def make_iv_all_plot(path, curves):
    p = Plot(1800, 1750)
    p.draw.text((45, 25), "W5 Pt/n-Si I-V grouped by gap label", fill=NAVY, font=get_font(34, True))
    p.draw.text((45, 70), "Display window -0.4 V to +0.8 V centers the transition and emphasizes the forward rise", fill=GRAY, font=get_font(21))
    for panel, gap in enumerate([10, 15, 20, 25, 30, 35]):
        panel_curves = []
        for idx, row in enumerate(range(1, 6)):
            c = curves[(row, gap)]
            mask = (c["v"] >= -0.4) & (c["v"] <= 0.8)
            panel_curves.append((f"Row {row}", c["v"][mask], c["j"][mask], COLORS[idx]))
        top = 110 + panel * 270
        p.panel((35, top, 1760, top + 250), panel_curves, "Voltage (V)", "J (A/cm^2)", f"Gap label {gap} um", xlim=(-0.4, 0.8), legend=True)
    p.save(path)


def make_representative_plots(linear_path, log_path, reps):
    series = []
    for label, c, color in reps:
        series.append((label, c["v"], c["j"], color))
    p = Plot(1600, 900)
    p.draw.text((45, 25), "Representative Ohmic-like and Schottky-like behavior", fill=NAVY, font=get_font(34, True))
    p.draw.text((45, 70), "Common -1 V to +1 V range; offset-corrected current density", fill=GRAY, font=get_font(21))
    p.panel((35, 115, 1565, 850), series, "Voltage (V)", "J (A/cm^2)", "Linear scale", xlim=(-1, 1), legend=True)
    p.save(linear_path)
    p2 = Plot(1600, 900)
    p2.draw.text((45, 25), "Rectification on logarithmic current scale", fill=NAVY, font=get_font(34, True))
    p2.draw.text((45, 70), "log10(|J|) highlights forward exponential rise and reverse leakage", fill=GRAY, font=get_font(21))
    p2.panel((35, 115, 1565, 850), series, "Voltage (V)", "log10(|J|), A/cm^2", "Semi-log magnitude", xlim=(-1, 1), legend=True, log_y=True)
    p2.save(log_path)


def make_bar_plot(path, labels, values, title, ylabel, highlight=None, log=False):
    p = Plot(1800, 950)
    p.draw.text((45, 25), title, fill=NAVY, font=get_font(34, True))
    p.draw.text((45, 70), "Calculated from offset-corrected I-V data", fill=GRAY, font=get_font(21))
    d = p.draw
    x0, y0, x1, y1 = 110, 130, 1740, 820
    vals = [math.log10(max(v, 1e-30)) if log else v for v in values]
    ymin = min(0, min(vals)) if not log else min(vals) - 0.2
    ymax = max(vals) * 1.08 if not log else max(vals) + 0.2
    d.rectangle((x0, y0, x1, y1), outline="#9CA3AF", width=2)
    for k in range(6):
        val = ymin + k * (ymax - ymin) / 5
        yy = y1 - k * (y1 - y0) / 5
        d.line((x0, yy, x1, yy), fill=LIGHT, width=1)
        d.text((55, yy - 10), f"{val:.1f}", fill="#374151", font=get_font(17))
    bw = (x1 - x0) / len(vals)
    for i, (lab, val) in enumerate(zip(labels, vals)):
        xa = x0 + i * bw + bw * 0.12
        xb = x0 + (i + 1) * bw - bw * 0.12
        yy = y1 - (val - ymin) / (ymax - ymin) * (y1 - y0)
        color = RED if highlight == i else BLUE
        d.rectangle((xa, yy, xb, y1), fill=color)
        d.text((xa, max(y0 + 2, yy - 24)), f"{val:.1f}", fill="#374151", font=get_font(13))
        d.text((xa, y1 + 10), lab, fill="#374151", font=get_font(14))
    d.text((x0, y0 - 32), ylabel, fill="#111827", font=get_font(20))
    d.text((110, 865), "Device label = row_gap", fill="#374151", font=get_font(19))
    p.save(path)


def make_cv_plot(path, cv_curves):
    p = Plot(1600, 950)
    p.draw.text((45, 25), "W5 Pt/n-Si capacitance-voltage characteristics", fill=NAVY, font=get_font(34, True))
    p.draw.text((45, 70), "10 kHz CP-RP measurements; nonnumeric O/R values excluded", fill=GRAY, font=get_font(21))
    series = []
    for i, (name, c) in enumerate(cv_curves.items()):
        mask = c["v"] <= 0.15
        series.append((name, c["v"][mask], c["c_pf"][mask], COLORS[i]))
    p.panel((35, 115, 1565, 900), series, "Bias voltage (V)", "Capacitance (pF)", "C-V curves", xlim=(-3, 0.15), legend=True)
    p.save(path)


def make_cv_fit_plot(path, cv_curves, cv_fits):
    p = Plot(1800, 1250)
    p.draw.text((45, 25), "1/C^2-V extraction of built-in potential", fill=NAVY, font=get_font(34, True))
    p.draw.text((45, 70), "Reverse/depletion region V <= 0 V; colored points=data, gray line=fit", fill=GRAY, font=get_font(21))
    for idx, (name, c) in enumerate(cv_curves.items()):
        row, col = divmod(idx, 2)
        box = (35 + col * 875, 115 + row * 360, 880 + col * 875, 455 + row * 360)
        mask = c["fit_mask"]
        x = c["v"][mask]
        y = c["inv_c2"][mask] / 1e22
        f = cv_fits[name]
        xf = np.linspace(float(np.min(x)), min(0.85, f["vbi"]), 100)
        yf = (f["slope"] * xf + f["intercept"]) / 1e22
        series = [("measured", x, y, COLORS[idx], True, 0), (f"linear fit R2={f['r2']:.5f}", xf, yf, GRAY, False, 3)]
        p.panel(box, series, "Bias voltage (V)", "1/C^2 (1e22 F^-2)", f"Measurement {name}: Vbi={f['vbi']:.3f} V", legend=True, scatter=False)
    p.save(path)


def make_cv_parameter_plot(path, fits):
    p = Plot(1700, 1000)
    p.draw.text((45, 25), "Extracted Schottky junction parameters", fill=NAVY, font=get_font(34, True))
    p.draw.text((45, 70), "A=pi(150 um)^2, T=300 K, eps_Si=11.7 eps0, Nc=2.8e19 cm^-3", fill=GRAY, font=get_font(21))
    labels = list(fits)
    vals = [fits[k] for k in labels]
    indices = np.arange(1, len(vals) + 1)
    series1 = [("Vbi", indices, [v["vbi"] for v in vals], BLUE), ("phiB", indices, [v["phi_b"] for v in vals], RED)]
    p.panel((35, 120, 830, 920), series1, "Measurement index", "Potential (V or eV)", "Built-in potential and barrier height", xlim=(1, len(vals)), ylim=(0.6, 1.08), legend=True, scatter=True)
    series2 = [("ND", indices, [v["nd"] / 1e15 for v in vals], GREEN)]
    p.panel((855, 120, 1665, 920), series2, "Measurement index", "ND (1e15 cm^-3)", "Donor concentration", xlim=(1, len(vals)), ylim=(1.05, 1.28), legend=True, scatter=True)
    p.save(path)


def analyze(args):
    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    temperature = args.temperature
    area = math.pi * (args.radius_um * 1e-4) ** 2
    vt = KB_EV * temperature

    iv_metrics = []
    iv_long = []
    curves = {}
    integrity = []
    for path in sorted((input_dir / "I-V").glob("*.csv")):
        m = re.match(r"^(\d+)_(\d+)um\.csv$", path.name)
        if not m:
            continue
        row, gap = int(m.group(1)), int(m.group(2))
        raw = read_csv(path)
        v0 = np.array([float(r["Voltage"]) for r in raw], dtype=float)
        i0raw = np.array([float(r["Current"]) for r in raw], dtype=float)
        (a, b), segments = longest_monotonic_segment(v0)
        v, current = v0[a:b], i0raw[a:b]
        mask = (v >= -1.0001) & (v <= 1.0001)
        vw, iw = v[mask], current[mask]
        offset = interp(vw, iw, 0.0)
        ic = iw - offset
        j = ic / area
        curves[(row, gap)] = {"v": vw, "i": ic, "j": j, "file": path.name}

        im1, ip1 = interp(vw, ic, -1.0), interp(vw, ic, 1.0)
        im05, ip05 = interp(vw, ic, -0.5), interp(vw, ic, 0.5)
        rr1 = abs(ip1) / max(abs(im1), 1e-30)
        rr05 = abs(ip05) / max(abs(im05), 1e-30)
        symmetry = max(abs(ip1), abs(im1)) / max(min(abs(ip1), abs(im1)), 1e-30)
        linmask = (vw >= -0.1) & (vw <= 0.1)
        lin = linear_fit(vw[linmask], ic[linmask])
        small_r = 1.0 / lin["slope"] if lin and lin["slope"] != 0 else float("nan")
        ff = forward_log_fit(vw, ic, temperature)
        if ff:
            flo, fhi, ideality, ffit = ff
            isat = math.exp(ffit["intercept"])
            phi_iv = vt * math.log(area * RICHARDSON_NSI * temperature**2 / isat) if isat > 0 else float("nan")
            fr2 = ffit["r2"]
        else:
            flo = fhi = ideality = isat = phi_iv = fr2 = float("nan")
        if rr1 >= 10 and fr2 >= 0.98:
            cls = "Schottky-like"
        elif symmetry <= 2 and lin and lin["r2"] >= 0.995:
            cls = "Near-ohmic"
        else:
            cls = "Nonideal/weakly rectifying"
        schottky_score = math.log10(max(rr1, 1e-30)) + (fr2 if math.isfinite(fr2) else 0) - min(abs(offset) / max(abs(ip1), 1e-30), 1)
        ohmic_score = (lin["r2"] if lin else 0) - abs(math.log10(max(symmetry, 1e-30)))
        complete = bool(len(v) >= 601 and np.min(v) <= -2.99 and np.max(v) >= 2.99)
        integrity.append({
            "File": path.name, "OriginalPoints": len(raw), "Segments": segments,
            "UsedSegmentStartIndex": a + 1, "UsedSegmentPoints": len(v),
            "Vmin_V": float(np.min(v)), "Vmax_V": float(np.max(v)),
            "CompleteMinus3ToPlus3": complete,
            "CommonWindowPoints": len(vw),
            "Flag": "restart; longest monotonic segment used" if segments > 1 else ("incomplete positive sweep" if not complete else "OK"),
        })
        metric = {
            "File": path.name, "DeviceRow": row, "GapLabel_um": gap,
            "Area_cm2": area, "Temperature_K": temperature,
            "ZeroCurrentOffset_A": offset,
            "Icorr_minus1V_A": im1, "Icorr_plus1V_A": ip1,
            "J_minus1V_A_cm2": im1 / area, "J_plus1V_A_cm2": ip1 / area,
            "RectificationRatio_0p5V": rr05, "RectificationRatio_1V": rr1,
            "SymmetryFactor_1V": symmetry,
            "NearZeroSlope_A_per_V": lin["slope"] if lin else float("nan"),
            "NearZeroResistance_Ohm": small_r,
            "NearZeroLinear_R2": lin["r2"] if lin else float("nan"),
            "ForwardFitStart_V": flo, "ForwardFitEnd_V": fhi,
            "ForwardLnI_R2": fr2, "IdealityFactor_n": ideality,
            "SaturationCurrent_A": isat, "BarrierHeight_IV_eV": phi_iv,
            "Classification": cls, "SchottkyScore": schottky_score, "OhmicScore": ohmic_score,
            "QualityFlag": "OK" if complete and segments == 1 else ("Restarted sweep" if segments > 1 else "Incomplete outside common window"),
        }
        iv_metrics.append(metric)
        for vv, iraw, icorr, jj in zip(vw, iw, ic, j):
            iv_long.append({"File": path.name, "DeviceRow": row, "GapLabel_um": gap,
                            "Voltage_V": vv, "CurrentRaw_A": iraw, "CurrentCorrected_A": icorr,
                            "CurrentDensity_A_cm2": jj})

    quality_candidates = [r for r in iv_metrics if r["QualityFlag"] == "OK"]
    best_s = max(quality_candidates, key=lambda r: r["SchottkyScore"])
    best_o = max(quality_candidates, key=lambda r: r["OhmicScore"])
    for r in iv_metrics:
        r["PresentationSelection"] = "Best Schottky-like" if r["File"] == best_s["File"] else ("Most Ohmic-like" if r["File"] == best_o["File"] else "")

    cv_long = []
    cv_fits = {}
    cv_curves = {}
    cv_integrity = []
    for path in sorted((input_dir / "C-V").glob("*.csv")):
        rows = read_csv(path)
        vkey = next(k for k in rows[0] if "Volt" in k)
        valid = []
        for r in rows:
            vv, cc, dd = as_float(r[vkey]), as_float(r["Capacitance[C]"]), as_float(r["DissipationFactor[D]"])
            if vv is not None and cc is not None and dd is not None and cc > 0:
                valid.append((vv, cc, dd, as_float(r["Freq[Hz]"]) or float("nan")))
        v = np.array([x[0] for x in valid])
        c = np.array([x[1] for x in valid])
        d = np.array([x[2] for x in valid])
        freq = np.array([x[3] for x in valid])
        inv = 1.0 / c**2
        fit_mask = (v <= 0.0) & (d <= args.max_dissipation)
        fit = linear_fit(v[fit_mask], inv[fit_mask])
        slope, intercept = fit["slope"], fit["intercept"]
        vbi = -intercept / slope
        dv_db = -1.0 / slope
        dv_dm = intercept / (slope**2)
        var_vbi = (dv_db**2 * fit["intercept_se"]**2 + dv_dm**2 * fit["slope_se"]**2 +
                   2 * dv_db * dv_dm * fit["cov_slope_intercept"])
        vbi_se = math.sqrt(max(0.0, var_vbi))
        nd = -2.0 / (Q * EPS_SI_REL * EPS0_F_PER_CM * area**2 * slope)
        nd_se = abs(nd * fit["slope_se"] / slope)
        phi_n = vt * math.log(NC_SI_CM3 / nd)
        phi_b = vbi + phi_n
        phi_b_se = math.sqrt(vbi_se**2 + (vt * nd_se / nd)**2)
        cv_fits[path.name] = {
            "File": path.name, "FitPointCount": int(np.sum(fit_mask)),
            "FitVmin_V": float(np.min(v[fit_mask])), "FitVmax_V": float(np.max(v[fit_mask])),
            "Slope_Fminus2_per_V": slope, "Slope_SE": fit["slope_se"],
            "Intercept_Fminus2": intercept, "Intercept_SE": fit["intercept_se"],
            "R2": fit["r2"], "RMSE_Fminus2": fit["rmse"],
            "Vbi_V": vbi, "Vbi_SE_V": vbi_se,
            "ND_cm3": nd, "ND_SE_cm3": nd_se,
            "Phi_n_eV": phi_n, "Phi_B_CV_eV": phi_b, "Phi_B_SE_eV": phi_b_se,
            "Area_cm2": area, "Temperature_K": temperature,
            "Nc_cm3": NC_SI_CM3, "EpsilonSi_F_per_cm": EPS_SI_REL * EPS0_F_PER_CM,
        }
        cv_curves[path.name] = {"v": v, "c_pf": c * 1e12, "d": d, "freq": freq, "inv_c2": inv, "fit_mask": fit_mask}
        cv_integrity.append({"File": path.name, "OriginalRows": len(rows), "ValidNumericRows": len(valid),
                             "ExcludedRows": len(rows) - len(valid), "Vmin_V": float(np.min(v)), "Vmax_V": float(np.max(v)),
                             "Frequency_Hz": float(np.median(freq)), "MaxDissipation": float(np.max(d))})
        for vv, cc, dd, ff, yy, used in zip(v, c, d, freq, inv, fit_mask):
            cv_long.append({"File": path.name, "Voltage_V": vv, "Frequency_Hz": ff,
                            "Capacitance_F": cc, "Capacitance_pF": cc * 1e12,
                            "DissipationFactor": dd, "InvC2_Fminus2": yy, "UsedForFit": bool(used)})

    fit_rows = list(cv_fits.values())
    mean_row = {"Statistic": "Mean"}
    sd_row = {"Statistic": "Sample SD"}
    for col in ["Vbi_V", "ND_cm3", "Phi_n_eV", "Phi_B_CV_eV", "R2"]:
        vals = np.array([r[col] for r in fit_rows], dtype=float)
        mean_row[col] = float(np.mean(vals))
        sd_row[col] = float(np.std(vals, ddof=1))
    cv_summary = [mean_row, sd_row]

    write_csv(output_dir / "iv_integrity.csv", integrity)
    write_csv(output_dir / "iv_metrics.csv", iv_metrics)
    write_csv(output_dir / "iv_common_window_data.csv", iv_long)
    write_csv(output_dir / "cv_integrity.csv", cv_integrity)
    write_csv(output_dir / "cv_cleaned_data.csv", cv_long)
    write_csv(output_dir / "cv_fit_summary.csv", fit_rows)
    write_csv(output_dir / "cv_parameter_statistics.csv", cv_summary)

    make_iv_all_plot(output_dir / "01_iv_all_common_window.png", curves)
    reps = [
        (f"Most Ohmic-like: {best_o['File']}", curves[(best_o["DeviceRow"], best_o["GapLabel_um"])], BLUE),
        (f"Best Schottky-like: {best_s['File']}", curves[(best_s["DeviceRow"], best_s["GapLabel_um"])], RED),
    ]
    make_representative_plots(output_dir / "02_iv_representatives_linear.png", output_dir / "03_iv_representatives_semilog.png", reps)
    ordered = sorted(iv_metrics, key=lambda r: (r["DeviceRow"], r["GapLabel_um"]))
    labels = [f"{r['DeviceRow']}_{r['GapLabel_um']}" for r in ordered]
    vals = [r["RectificationRatio_1V"] for r in ordered]
    hi = next(i for i, r in enumerate(ordered) if r["File"] == best_s["File"])
    make_bar_plot(output_dir / "04_rectification_ratio.png", labels, vals, "Rectification ratio at +/-1 V", "log10(|I(+1 V)| / |I(-1 V)|)", hi, log=True)
    make_cv_plot(output_dir / "05_cv_curves.png", cv_curves)
    make_cv_fit_plot(output_dir / "06_cv_inverse_square_fits.png", cv_curves, {k: {"slope": v["Slope_Fminus2_per_V"], "intercept": v["Intercept_Fminus2"], "r2": v["R2"], "vbi": v["Vbi_V"]} for k, v in cv_fits.items()})
    make_cv_parameter_plot(output_dir / "07_cv_extracted_parameters.png", {k: {"vbi": v["Vbi_V"], "nd": v["ND_cm3"], "phi_b": v["Phi_B_CV_eV"]} for k, v in cv_fits.items()})

    notes = f"""# W5 Pt/n-Si Schottky analysis

## Processing decisions

- The presentation I-V range is limited to the common -1 V to +1 V interval, as requested. Raw CSV files are unchanged.
- Current offset is the interpolated current at 0 V. Corrected current is `I_raw - I(0)`.
- `{next(x['File'] for x in integrity if x['Segments'] > 1)}` contains a restarted sweep; only its longest monotonic segment is used.
- Incomplete positive sweeps are retained because every file covers the common -1 V to +1 V interval.
- File gap values are treated as device/site labels, not CTLM transport lengths. The handout specifies a vertical Pt-electrode-to-stage Schottky measurement.
- C-V nonnumeric `O/R` rows are excluded. The fit uses numeric points with V <= 0 V and D <= {args.max_dissipation:g}.

## Constants and equations

- Circular Pt electrode radius: {args.radius_um:g} um; area = {area:.6e} cm^2
- Temperature: {temperature:g} K; silicon relative permittivity: {EPS_SI_REL:g}; Nc = {NC_SI_CM3:.3e} cm^-3
- `1/C^2 = 2(Vbi-V)/(q eps_Si ND A^2)`
- `ND = -2/(q eps_Si A^2 slope)`
- `Vbi = -intercept/slope`
- `phi_n = (kT/q) ln(Nc/ND)` and `phi_B = Vbi + phi_n`

## Main results

- Best Schottky-like I-V by the predefined score: **{best_s['File']}**, RR(+/-1 V)={best_s['RectificationRatio_1V']:.3g}, forward ln(I)-V R2={best_s['ForwardLnI_R2']:.5f}, n={best_s['IdealityFactor_n']:.3f}.
- Most Ohmic-like measurement: **{best_o['File']}**. This is a relative label and does not imply an ideal Ohmic contact.
- Mean Vbi = {mean_row['Vbi_V']:.4f} +/- {sd_row['Vbi_V']:.4f} V.
- Mean ND = {mean_row['ND_cm3']:.4e} +/- {sd_row['ND_cm3']:.4e} cm^-3.
- Mean phi_B(C-V) = {mean_row['Phi_B_CV_eV']:.4f} +/- {sd_row['Phi_B_CV_eV']:.4f} eV.

## Interpretation limits

- I-V thermionic-emission values are diagnostic because series resistance, barrier inhomogeneity and current-offset artifacts can distort the fitted ideality factor and I-V barrier height.
- The C-V extraction follows the course handout and is the primary quantitative result.
"""
    (output_dir / "analysis_notes.md").write_text(notes, encoding="utf-8")
    print(f"Wrote W5 analysis to {output_dir}")
    print(f"Best Schottky-like: {best_s['File']}; most Ohmic-like: {best_o['File']}")
    print(f"Mean Vbi={mean_row['Vbi_V']:.6f} V, ND={mean_row['ND_cm3']:.6e} cm^-3, phiB={mean_row['Phi_B_CV_eV']:.6f} eV")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", default="w5_data")
    parser.add_argument("--output-dir", default="output/w5_analysis")
    parser.add_argument("--radius-um", type=float, default=150.0)
    parser.add_argument("--temperature", type=float, default=300.0)
    parser.add_argument("--max-dissipation", type=float, default=0.1)
    analyze(parser.parse_args())
