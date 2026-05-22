import { Controller } from "@hotwired/stimulus";
import * as XLSX from "xlsx";

const XLSXLib = XLSX && XLSX.read ? XLSX : window.XLSX;

// Compares an uploaded XLSX against expected KPI mappings and renders a per-KPI
// status table. Listens for the custom `upload:complete` event fired by the file
// upload component, then uses SheetJS to parse the workbook client-side.
export default class extends Controller {
  static targets = ["output"];

  connect() {
    this.handleUploadBound = this.handleUpload.bind(this);
    document.addEventListener("upload:complete", this.handleUploadBound);
  }

  disconnect() {
    document.removeEventListener("upload:complete", this.handleUploadBound);
  }

  handleUpload(event) {
    const { file, uploadId } = event.detail;
    const controllerUploadId = this.element.dataset.uploadId;
    const targetId = event.target?.id || event.target?.closest?.("[id]")?.id;

    // Accept the event when uploadId matches exactly, or when uploadId is absent
    // but the event target's id matches (fallback for upload libs that omit uploadId).
    const idMatches = uploadId && controllerUploadId && uploadId === controllerUploadId;
    const fallbackMatches =
      !uploadId &&
      controllerUploadId &&
      (targetId === controllerUploadId ||
        targetId?.includes(controllerUploadId) ||
        controllerUploadId.includes(targetId || ""));

    if (!idMatches && !fallbackMatches) return;

    const reportedKpis = JSON.parse(this.element.dataset.reportedKpis || "[]");

    const reader = new FileReader();
    reader.onload = (e) => {
      try {
        const lib = (XLSX && XLSX.read) ? XLSX : window.XLSX;
        if (!lib || typeof lib.read !== "function") throw new Error("XLSX library unavailable");
        const data = new Uint8Array(e.target.result);
        const workbook = lib.read(data, { type: "array" });
        this.analyzeWorkbook(workbook, reportedKpis);
      } catch (err) {
        this.outputTarget.innerHTML =
          `<div class="alert alert-danger">` +
          `<strong>Please fix these errors before submitting.</strong> ` +
          `Failed to parse the uploaded file: ${err.message}</div>`;
        this.setSubmitGuard(true);
      }
    };
    reader.onerror = () => {
      this.outputTarget.innerHTML =
        `<div class="alert alert-danger">Failed to read the uploaded file.</div>`;
      this.setSubmitGuard(true);
    };
    reader.readAsArrayBuffer(file);
  }

  analyzeWorkbook(workbook, reportedKpis) {
    const normalize = (str) => (str || "").toString().replace(/\s+/g, "").toLowerCase();
    const results = [];
    const errors = [];

    workbook.SheetNames.forEach((sheetName) => {
      const sheet = workbook.Sheets[sheetName];
      if (!sheet["!ref"]) {
        errors.push(`Sheet '${sheetName}' is empty or invalid.`);
        return;
      }

      const data = XLSXLib.utils.sheet_to_json(sheet, { header: 1 });
      if (data.length === 0) {
        errors.push(`Sheet '${sheetName}' is empty.`);
        return;
      }

      const headerRow = data[0] || [];
      const periodColumns = headerRow.slice(1).filter((v) => this.isDateLike(v));

      if (periodColumns.length < 1) {
        errors.push(
          `Invalid or missing header row in sheet '${sheetName}'. ` +
          `Expected date-like values (e.g. Jan 24, FY24, Q1FY25). ` +
          `Found: ${headerRow.slice(1).join(", ")}`
        );
        return;
      }

      const hasKpiNames = data.length > 1 &&
        data.some((r, i) => i > 0 && r[0] && r[0].toString().trim() !== "");
      if (!hasKpiNames) {
        errors.push(
          `Missing KPI names in sheet '${sheetName}'. The first column should contain KPI names.`
        );
        return;
      }

      const periodCount = periodColumns.length;

      reportedKpis.forEach((kpiObj) => {
        const row = data.find((r) => normalize(r[0]) === normalize(kpiObj.reported_kpi_name));
        if (!row) return;

        const nonBlankCount = row
          .slice(1)
          .filter((v) => v !== null && v !== undefined && v.toString().trim() !== "")
          .length;

        results.push({ sheet: sheetName, kpi: kpiObj.reported_kpi_name, nonBlankCount, periodCount });
      });
    });

    if (errors.length > 0) {
      this.outputTarget.innerHTML =
        `<div class="alert alert-danger">Errors:<ul>${errors.map((e) => `<li>${e}</li>`).join("")}</ul>` +
        `<strong>Please fix these errors before submitting.</strong></div>`;
      this.setSubmitGuard(true);
      return;
    }

    const foundNames = new Set(results.map((r) => normalize(r.kpi)));
    const missing = reportedKpis
      .filter((k) => !foundNames.has(normalize(k.reported_kpi_name)))
      .map((k) => k.reported_kpi_name);

    this.renderReport(results, missing, reportedKpis.length);
  }

  renderReport(results, missing, totalKpis) {
    const foundCount = totalKpis - missing.length;
    let html = "<div class='card card-body'>";

    if (missing.length > 0) {
      html +=
        `<div class="alert alert-warning">` +
        `${foundCount} of ${totalKpis} KPIs found. ` +
        `Missing: ${missing.join(", ")}. ` +
        `You can still submit — missing KPIs will not be imported.` +
        `</div>`;
    } else {
      html += `<div class="alert alert-success">All ${totalKpis} KPIs found.</div>`;
    }

    const allKpis = [
      ...results.map((r) => ({ ...r, present: true })),
      ...missing.map((m) => ({ sheet: "-", kpi: m, nonBlankCount: 0, periodCount: 0, present: false })),
    ];

    if (allKpis.length > 0) {
      html += `<table class="table table-bordered table-sm">
        <thead><tr><th>Status</th><th>Sheet</th><th>KPI</th><th>Non-Blank Values</th></tr></thead>
        <tbody>`;
      allKpis.forEach((r) => {
        const icon = r.present
          ? '<span style="color:green;">&#10004;</span>'
          : '<span style="color:red;">&#10008;</span>';
        const valueDisplay = r.present ? `${r.nonBlankCount} / ${r.periodCount}` : "-";
        html += `<tr><td>${icon}</td><td>${r.sheet}</td><td>${r.kpi}</td><td>${valueDisplay}</td></tr>`;
      });
      html += "</tbody></table>";
    }

    html += "</div>";
    this.outputTarget.innerHTML = html;
    this.setSubmitGuard(false);
  }

  // Disables or re-enables all submit buttons marked with data-kpi-submit-guard.
  // Only portco form buttons carry this attribute, so fund admin forms are unaffected.
  setSubmitGuard(blocked) {
    document.querySelectorAll("[data-kpi-submit-guard]").forEach((el) => {
      el.disabled = blocked;
    });
  }

  // Returns true if a cell value looks like a date/period header.
  // Mirrors KpiDateUtils.date_like? on the Ruby side.
  isDateLike(v) {
    if (!v) return false;

    // Numeric Excel date serials (e.g. 45689 → 2025-02-15)
    if (!isNaN(v) && v > 10000 && v < 60000) return true;

    const s = v.toString().trim();

    // "Jan-24", "Feb-24", "Mar-25" shorthand
    if (/\b(?:JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|SEPT|OCT|NOV|DEC)[-'']?\d{2,4}\b/i.test(s)) return true;

    const patterns = [
      /\bH[12](?:\s?FY)?\s?\d{2,4}\b/i,                                                                                          // H1 2023, H2FY23
      /\bQ[1-4][-' ]?(?:FY|CY)?\d{2,4}\b/i,                                                                                      // Q1FY25, Q3CY22
      /\bFY\s?\d{2,4}[-–]\d{2,4}\b/i,                                                                                             // FY2020-21
      /\b(?:FY|CY)\s?\d{2,4}\b/i,                                                                                                 // FY23, CY2024
      /\b(?:JAN(?:UARY)?|FEB(?:RUARY)?|MAR(?:CH)?|APR(?:IL)?|MAY|JUN(?:E)?|JUL(?:Y)?|AUG(?:UST)?|SEP(?:T(?:EMBER)?)?|OCT(?:OBER)?|NOV(?:EMBER)?|DEC(?:EMBER)?)\s+\d{2,4}\b/i, // Jan 24, September 2024
      /\b(?:JFM|AMJ|JAS|OND)\s+\d{4}\b/i,                                                                                        // JFM 2021
      /\b(?:JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|SEPT|OCT|NOV|DEC)-(?:JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|SEPT|OCT|NOV|DEC)\s+\d{4}\b/i, // Jan-Mar 2021
      /\b\d{2}[-/]\d{2}[-/]\d{2,4}\b/,                                                                                            // 01-11-2024
      /\b\d{4}\b/,                                                                                                                 // plain year
    ];

    return patterns.some((p) => p.test(s));
  }
}
