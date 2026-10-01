import fs from "node:fs/promises";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const root = process.cwd();
const sourceDir = `${root}/output/w5_analysis`;
const outputDir = `${root}/outputs/w5_schottky_excel`;
const outputPath = `${outputDir}/W5_Schottky_analysis.xlsx`;
const previewDir = `${root}/tmp/xlsx/w5_previews`;

function parseCsv(text) {
  const rows = []; let row = [], field = "", quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') { field += '"'; i++; }
      else if (c === '"') quoted = false;
      else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ',') { row.push(field); field = ""; }
    else if (c === '\n') { row.push(field.replace(/\r$/, "")); rows.push(row); row = []; field = ""; }
    else field += c;
  }
  if (field.length || row.length) { row.push(field.replace(/\r$/, "")); rows.push(row); }
  return rows.filter(r => r.some(v => v !== ""));
}

function typedRows(rows) {
  return rows.map((r, ri) => r.map((v, ci) => {
    if (ri === 0) return ci === 0 ? v.replace(/^\uFEFF/, "") : v;
    if (v === "") return "";
    if (/^(True|False)$/i.test(v)) return /^true$/i.test(v);
    if (/^[+-]?(?:\d+\.?\d*|\.\d+)(?:[Ee][+-]?\d+)?$/.test(v)) return Number(v);
    return v;
  }));
}

async function readCsv(name) { return typedRows(parseCsv(await fs.readFile(`${sourceDir}/${name}`, "utf8"))); }
const [ivMetrics, ivData, ivAudit, cvData, cvFits, cvStats, cvAudit] = await Promise.all([
  readCsv("iv_metrics.csv"), readCsv("iv_common_window_data.csv"), readCsv("iv_integrity.csv"),
  readCsv("cv_cleaned_data.csv"), readCsv("cv_fit_summary.csv"), readCsv("cv_parameter_statistics.csv"), readCsv("cv_integrity.csv"),
]);

function records(rows) {
  const h = rows[0]; return rows.slice(1).map(r => Object.fromEntries(h.map((k, i) => [k, r[i]])));
}
const metrics = records(ivMetrics), iv = records(ivData), cv = records(cvData), fits = records(cvFits);
const bestS = metrics.find(r => r.PresentationSelection === "Best Schottky-like");
const bestO = metrics.find(r => r.PresentationSelection === "Most Ohmic-like");

const wb = Workbook.create();
const summary = wb.worksheets.add("Summary");
const reps = wb.worksheets.add("IV Representatives");
const metricSheet = wb.worksheets.add("IV Metrics");
const rowSheets = [1,2,3,4,5].map(n => wb.worksheets.add(`IV Row ${n}`));
const cvCurves = wb.worksheets.add("CV Curves");
const cvFitSheet = wb.worksheets.add("CV Fits");
const cvParam = wb.worksheets.add("CV Parameters");
const ivAuditSheet = wb.worksheets.add("IV Audit");
const cvDataSheet = wb.worksheets.add("CV Data");
const method = wb.worksheets.add("Method");
const sheets = [summary, reps, metricSheet, ...rowSheets, cvCurves, cvFitSheet, cvParam, ivAuditSheet, cvDataSheet, method];

const font = "Arial", navy = "#17365D", blue = "#2563EB", red = "#E11D48", green = "#059669";
const purple = "#7C3AED", orange = "#D97706", teal = "#0891B2", dark = "#1F2937", gray = "#6B7280";
const colors = [blue, red, green, purple, orange, teal];

function title(sheet, text, subtitle) {
  sheet.getRange("A2").values = [[text]];
  sheet.getRange("A2").format.font = { name: font, size: 16, bold: true, color: dark };
  sheet.getRange("A3").values = [[subtitle]];
  sheet.getRange("A3").format.font = { name: font, size: 10, italic: true, color: gray };
  sheet.getRange("A4:Q4").format.borders = { bottom: { style: "thin", color: navy } };
}
function styleTable(sheet, range, header) {
  sheet.getRange(range).format.font = { name: font, size: 10, color: dark };
  sheet.getRange(header).format = { fill: navy, font: { name: font, size: 10, bold: true, color: "#FFFFFF" }, horizontalAlignment: "center", verticalAlignment: "center", wrapText: true };
}
function lineChart(sheet, sources, start, end, chartTitle, xTitle, yTitle, palette=colors, legend=true) {
  const chart = sheet.charts.add("line", sources);
  chart.setPosition(start, end); chart.title = chartTitle; chart.hasLegend = legend;
  chart.titleTextStyle.fontSize = 12; chart.titleTextStyle.typeface = font;
  if (legend) chart.legend = { position: "top", textStyle: { typeface: font, fontSize: 9 } };
  chart.xAxis = { axisType: "textAxis", textStyle: { typeface: font, fontSize: 9 } };
  chart.yAxis = { numberFormatCode: "0.00E+00", numberFormatSourceLinked: false, textStyle: { typeface: font, fontSize: 9 } };
  chart.xAxis.title.text = xTitle; chart.yAxis.title.text = yTitle;
  chart.series.items.forEach((s, i) => { s.line = { fill: palette[i % palette.length], style: i === 0 ? "solid" : "dashed", width: 2 }; s.fill = palette[i % palette.length]; });
  return chart;
}

for (const s of sheets) { s.showGridLines = false; s.getRange("A1:Q240").format.font = { name: font, size: 10, color: dark }; }

// Summary and constants used by formulas.
title(summary, "W5 Pt/n-Si Schottky analysis", "I-V limited to the common -1 V to +1 V window; C-V extraction follows the course handout");
summary.getRange("A6:B14").values = [
  ["Main result", "Value"],
  ["Best Schottky-like I-V", bestS.File], ["Most Ohmic-like I-V", bestO.File],
  ["Mean Vbi (V)", null], ["Vbi sample SD (V)", null],
  ["Mean ND (cm^-3)", null], ["ND sample SD (cm^-3)", null],
  ["Mean phi_B(C-V) (eV)", null], ["phi_B sample SD (eV)", null],
];
summary.getRange("B9:B14").formulas = [["=AVERAGE('CV Parameters'!J6:J10)"],["=STDEV.S('CV Parameters'!J6:J10)"],["=AVERAGE('CV Parameters'!L6:L10)"],["=STDEV.S('CV Parameters'!L6:L10)"],["=AVERAGE('CV Parameters'!O6:O10)"],["=STDEV.S('CV Parameters'!O6:O10)"]];
styleTable(summary, "A6:B14", "A6:B6");
summary.getRange("A18:B24").values = [
  ["Constant", "Value"], ["q (C)", 1.602176634e-19], ["epsilon_Si (F/cm)", 11.7*8.8541878128e-14],
  ["Pt disk area (cm^2)", Math.PI*Math.pow(150e-4,2)], ["Temperature (K)", 300], ["Nc for Si (cm^-3)", 2.8e19], ["kT/q (V)", 8.617333262e-5*300],
];
styleTable(summary, "A18:B24", "A18:B18");
summary.getRange("D6:E13").values = [
  ["Interpretation", "Conclusion"],
  ["I-V", "Most measurements are strongly rectifying; the Ohmic-like label is relative, not ideal Ohmic behavior."],
  ["C-V", "Reverse-bias 1/C^2-V is highly linear and supports depletion-capacitance extraction."],
  ["Geometry", "Circular Pt electrode diameter 300 um (radius 150 um)."],
  ["Connection", "HIGH to Pt electrode and LOW to stage; file gap is treated as a site label, not CTLM length."],
  ["Primary values", "Vbi, ND, phi_n and phi_B(C-V) are calculated from the course equations."],
  ["I-V fit", "n, Is and phi_B(I-V) are diagnostic because nonideality and series resistance affect them."],
  ["Data quality", "Restarted and incomplete full sweeps remain audited; every file covers the common -1 to +1 V range."],
];
styleTable(summary, "D6:E13", "D6:E6"); summary.getRange("E7:E13").format.wrapText = true;

// Full metrics and audits.
title(metricSheet, "I-V metrics and classification", "Offset-corrected values, common -1 V to +1 V range");
metricSheet.getRange("A5").write(ivMetrics); styleTable(metricSheet, `A5:AC${4+ivMetrics.length}`, "A5:AC5");
title(ivAuditSheet, "I-V data integrity audit", "Sweep restarts and incomplete positive-bias ranges are explicitly flagged");
ivAuditSheet.getRange("A5").write(ivAudit); styleTable(ivAuditSheet, `A5:J${4+ivAudit.length}`, "A5:J5");

// Representative curves with formula-driven log helper columns.
title(reps, "Representative I-V comparison", "Native Excel charts; selected only from complete, non-restarted sweeps");
const oData = iv.filter(r => r.File === bestO.File), sData = iv.filter(r => r.File === bestS.File);
reps.getRange("A6:E6").values = [["Voltage (V)", `Most Ohmic-like J: ${bestO.File}`, `Best Schottky-like J: ${bestS.File}`, "log10(abs(J Ohmic-like))", "log10(abs(J Schottky-like))"]];
for (let i=0;i<oData.length;i++) {
  const r=7+i; reps.getRange(`A${r}:C${r}`).values = [[oData[i].Voltage_V, oData[i].CurrentDensity_A_cm2, sData[i].CurrentDensity_A_cm2]];
  reps.getRange(`D${r}:E${r}`).formulas = [[`=LOG10(MAX(ABS(B${r}),1E-30))`,`=LOG10(MAX(ABS(C${r}),1E-30))`]];
}
const repLast = 6 + oData.length; styleTable(reps, `A6:E${repLast}`, "A6:E6");
lineChart(reps, reps.getRange(`A6:C${repLast}`), "G6", "P27", "Representative I-V on linear scale", "Voltage (V)", "J (A/cm^2)", [blue, red], true);
lineChart(reps, [reps.getRange(`A6:A${repLast}`), reps.getRange(`D6:D${repLast}`), reps.getRange(`E6:E${repLast}`)], "G29", "P50", "Representative I-V on log magnitude scale", "Voltage (V)", "log10(|J|)", [blue, red], true);

// One editable chart per device row.
for (let row=1; row<=5; row++) {
  const sh = rowSheets[row-1]; title(sh, `I-V curves: device row ${row}`, "Offset-corrected current density in the common -1 V to +1 V window");
  const gaps=[10,15,20,25,30,35]; const first=iv.filter(r=>r.DeviceRow===row && r.GapLabel_um===10).sort((a,b)=>a.Voltage_V-b.Voltage_V);
  const byGap = new Map(gaps.map(g => [g, iv.filter(r=>r.DeviceRow===row && r.GapLabel_um===g).sort((a,b)=>a.Voltage_V-b.Voltage_V)]));
  sh.getRange("A6:G6").values = [["Voltage (V)", ...gaps.map(g=>`${g} um`)]];
  for (let i=0;i<first.length;i++) {
    const values=[first[i].Voltage_V];
    for (const gap of gaps) values.push(byGap.get(gap)[i]?.CurrentDensity_A_cm2 ?? "");
    sh.getRange(`A${7+i}:G${7+i}`).values=[values];
  }
  const last=6+first.length; styleTable(sh, `A6:G${last}`, "A6:G6");
  lineChart(sh, sh.getRange(`A6:G${last}`), "I6", "Q29", `Row ${row}: I-V comparison`, "Voltage (V)", "J (A/cm^2)", colors, true);
}

// C-V source data and combined chart.
title(cvDataSheet, "Cleaned C-V source data", "Nonnumeric O/R rows removed; UsedForFit marks the reverse-depletion regression points");
cvDataSheet.getRange("A5").write(cvData); styleTable(cvDataSheet, `A5:H${4+cvData.length}`, "A5:H5");
title(cvCurves, "Capacitance-voltage curves", "10 kHz CP-RP data; all five measurements shown as editable Excel series");
const cvFiles=["1.csv","2.csv","3.csv","4.csv","5.csv"], grid=[];
for(let k=0;k<=51;k++) grid.push(Number((-3+k*0.1).toFixed(1)));
cvCurves.getRange("A6:F6").values=[["Bias voltage (V)",...cvFiles]];
for(let i=0;i<grid.length;i++) {
  const values=[grid[i]];
  for(const f of cvFiles) { const q=cv.find(r=>r.File===f && Math.abs(r.Voltage_V-grid[i])<1e-6); values.push(q ? q.Capacitance_pF : ""); }
  cvCurves.getRange(`A${7+i}:F${7+i}`).values=[values];
}
styleTable(cvCurves, `A6:F${6+grid.length}`, "A6:F6");
lineChart(cvCurves, cvCurves.getRange(`A6:F${6+grid.length}`), "H6", "Q30", "C-V comparison", "Bias voltage (V)", "Capacitance (pF)", colors, true);

// C-V parameters: raw regression coefficients plus live Excel formulas.
title(cvParam, "C-V extracted parameters", "Vbi, ND, phi_n and phi_B are formula-driven from the fitted slope/intercept and Summary constants");
cvParam.getRange("A5:P5").values=[["File","Fit N","Fit Vmin","Fit Vmax","Slope","Slope SE","Intercept","Intercept SE","R2","Vbi (V)","Vbi SE","ND (cm^-3)","ND SE","phi_n (eV)","phi_B (eV)","phi_B SE"]];
for(let i=0;i<fits.length;i++) {
  const f=fits[i], r=6+i;
  cvParam.getRange(`A${r}:I${r}`).values=[[f.File,f.FitPointCount,f.FitVmin_V,f.FitVmax_V,f.Slope_Fminus2_per_V,f.Slope_SE,f.Intercept_Fminus2,f.Intercept_SE,f.R2]];
  cvParam.getRange(`J${r}`).formulas=[[`=-G${r}/E${r}`]]; cvParam.getRange(`K${r}`).values=[[f.Vbi_SE_V]];
  cvParam.getRange(`L${r}`).formulas=[[`=-2/(Summary!$B$19*Summary!$B$20*Summary!$B$21^2*E${r})`]]; cvParam.getRange(`M${r}`).values=[[f.ND_SE_cm3]];
  cvParam.getRange(`N${r}`).formulas=[[`=Summary!$B$24*LN(Summary!$B$23/L${r})`]]; cvParam.getRange(`O${r}`).formulas=[[`=J${r}+N${r}`]]; cvParam.getRange(`P${r}`).values=[[f.Phi_B_SE_eV]];
}
styleTable(cvParam,"A5:P10","A5:P5");
cvParam.getRange("R5:U10").values=[["Index","Vbi","phi_B","ND (1e15 cm^-3)"],[1,null,null,null],[2,null,null,null],[3,null,null,null],[4,null,null,null],[5,null,null,null]];
for(let r=6;r<=10;r++) cvParam.getRange(`S${r}:U${r}`).formulas=[[`=J${r}`,`=O${r}`,`=L${r}/1E15`]];
styleTable(cvParam,"R5:U10","R5:U5");
lineChart(cvParam, [cvParam.getRange("R5:R10"),cvParam.getRange("S5:S10"),cvParam.getRange("T5:T10")], "R13", "Z30", "Built-in potential and barrier height", "Measurement", "Potential (V or eV)", [blue,red], true);
lineChart(cvParam, [cvParam.getRange("R5:R10"),cvParam.getRange("U5:U10")], "R32", "Z49", "Donor concentration", "Measurement", "ND (1e15 cm^-3)", [green], false);

// Individual 1/C^2-V fits and x-intercepts.
title(cvFitSheet, "1/C^2-V fits", "Colored measured points and formula-linked linear fits extrapolated to the x-intercept");
for(let i=0;i<cvFiles.length;i++) {
  const f=cvFiles[i], fit=fits.find(x=>x.File===f), start=6+i*32;
  const source=cv.filter(r=>r.File===f && r.UsedForFit===true);
  cvFitSheet.getRange(`A${start}:C${start}`).values=[[`${f} V`,"Measured 1/C^2 (1e22 F^-2)","Linear fit 1/C^2 (1e22 F^-2)"]];
  const prow=6+i;
  for(let j=0;j<source.length;j++) {
    const r=start+1+j; cvFitSheet.getRange(`A${r}:B${r}`).values=[[source[j].Voltage_V,source[j].InvC2_Fminus2/1e22]];
    cvFitSheet.getRange(`C${r}`).formulas=[[`=('CV Parameters'!E${prow}*A${r}+'CV Parameters'!G${prow})/1E22`]];
  }
  const xrow=start+1+source.length; cvFitSheet.getRange(`A${xrow}`).formulas=[[`='CV Parameters'!J${prow}`]]; cvFitSheet.getRange(`C${xrow}`).values=[[0]];
  const last=xrow; styleTable(cvFitSheet,`A${start}:C${last}`,`A${start}:C${start}`);
  lineChart(cvFitSheet,cvFitSheet.getRange(`A${start}:C${last}`),`G${start}`,`P${start+22}`,`${f}: Vbi=${fit.Vbi_V.toFixed(3)} V, R2=${fit.R2.toFixed(5)}`,"Bias voltage (V)","1/C^2 (1e22 F^-2)",[colors[i],gray],true);
}

title(method, "Method and equations", "Assumptions, quality rules and interpretation limits");
method.getRange("A6:B19").values=[
  ["Item","Description"], ["Device","Pt 40 nm on non-degenerate n-Si; 400 C silicidation per device specification"],
  ["Electrode","Circular Pt disk diameter 300 um; radius 150 um"], ["I-V window","Only -1 V to +1 V is used in presentation and classification"],
  ["Offset correction","I_corrected = I_raw - interpolated I(0)"], ["Rectification ratio","abs(I(+V))/abs(I(-V)), reported at 0.5 V and 1 V"],
  ["Ohmic-like criterion","Symmetry and near-zero linearity; label is relative unless the ideal criterion is met"],
  ["Schottky criterion","RR at 1 V >= 10 and forward ln(I)-V R2 >= 0.98"],
  ["C-V fit","Numeric data with V <= 0 V and dissipation factor D <= 0.1"],
  ["ND","-2/(q*epsilon_Si*A^2*slope)"], ["Vbi","-intercept/slope (x-intercept of 1/C^2-V)"],
  ["phi_n","(kT/q)*LN(Nc/ND)"], ["phi_B","Vbi + phi_n"],
  ["Limit","I-V thermionic parameters are diagnostic; C-V is the primary quantitative extraction requested by the handout"],
];
styleTable(method,"A6:B19","A6:B6"); method.getRange("B7:B19").format.wrapText=true;

for(const s of sheets){ const used=s.getUsedRange(); used.format.autofitColumns(); used.format.autofitRows(); }
summary.getRange("A:A").format.columnWidth=28; summary.getRange("B:B").format.columnWidth=20; summary.getRange("D:D").format.columnWidth=20; summary.getRange("E:E").format.columnWidth=90;
method.getRange("A:A").format.columnWidth=24; method.getRange("B:B").format.columnWidth=100;
metricSheet.getRange("A:AC").format.columnWidth=17; cvDataSheet.getRange("A:H").format.columnWidth=18; cvParam.getRange("A:P").format.columnWidth=16;

wb.recalculate(); await fs.mkdir(outputDir,{recursive:true}); await fs.mkdir(previewDir,{recursive:true});
const check=await wb.inspect({kind:"table",range:"Summary!A6:E24",include:"values,formulas",tableMaxRows:25,tableMaxCols:8,maxChars:9000}); console.log("SUMMARY\n"+check.ndjson);
const errors=await wb.inspect({kind:"match",searchTerm:"#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!",options:{useRegex:true,maxResults:100},summary:"final formula error scan"}); console.log("ERRORS\n"+errors.ndjson);
const drawings=await wb.inspect({kind:"drawing",maxChars:15000}); console.log("DRAWINGS\n"+drawings.ndjson);
for(const s of sheets){ const preview=await wb.render({sheetName:s.name,autoCrop:"all",scale:0.8,format:"png"}); await fs.writeFile(`${previewDir}/${s.name.replace(/ /g,"_")}.png`,new Uint8Array(await preview.arrayBuffer())); }
const output=await SpreadsheetFile.exportXlsx(wb); await output.save(outputPath); console.log(`OUTPUT=${outputPath}`);
