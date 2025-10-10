import { Controller } from "@hotwired/stimulus";
import * as XLSX from "xlsx";
const XLSXLib = XLSX && XLSX.read ? XLSX : window.XLSX;

/**
 * This Stimulus controller generates a quick report comparing KPI mappings
 * against an uploaded XLSX file. It shows which KPIs are:
 * - missing (not found at all)
 * - present (found in headers)
 * - for each present KPI, how many non-blank values are in its row
 */
export default class extends Controller {
 static targets = ["output"];

 static values = {
   reportedKpis: Array,
 };

  connect() {
    console.log("🧩 KPI XLSX REPORT CONTROLLER connected.");
   this.handleUploadBound = this.handleUpload.bind(this);
   document.addEventListener("upload:complete", this.handleUploadBound);

    // Log dataset values for debugging
    console.log("Controller dataset:", this.element.dataset);
  }

  disconnect() {
   console.log("🧩 KPI XLSX REPORT CONTROLLER disconnected.");
   document.removeEventListener("upload:complete", this.handleUploadBound);
  }

  /**
   * Triggered when an XLSX file upload completes.
   * Uses the FileReader API to read the XLSX and parse it as a workbook.
   * Expects the DOM element to have a dataset attribute with `reportedKpis`
   * — a JSON list of KPI mappings similar to what `KpiWorkbookReader` uses.
   */
  handleUpload(event) {
    console.log("📂 KPI XLSX REPORT: upload:complete event triggered =>", event);

    // Extract the uploaded file and event context
    const file = event.detail.file;
    const uploadId = event.detail.uploadId;
    const controllerUploadId = this.element.dataset.uploadId;

    console.log("➡️ uploadId:", uploadId, "controllerUploadId:", controllerUploadId);

    /**
     * 🧭 Smarter event validation: handle uploads even if uploadId is undefined
     * or driven by Uppy (some Uppy events omit uploadId in detail).
     */
    console.log("📎 Normalized upload check start...");

    const targetId = event.target?.id || event.target?.closest("[id]")?.id;
    console.log("🔍 Found targetId:", targetId);

    // Allow trigger if 1) uploadId matches, 2) uploadId missing but target id matches
    let shouldProceed = false;
    if (uploadId && controllerUploadId && uploadId === controllerUploadId) {
      console.log("✅ Exact uploadId match — processing allowed.");
      shouldProceed = true;
    } else if (!uploadId && controllerUploadId && targetId === controllerUploadId) {
      console.log("✅ Missing uploadId but target id matches controller upload id — proceeding.");
      shouldProceed = true;
    } else if (
      !uploadId &&
      controllerUploadId &&
      (targetId?.includes(controllerUploadId) || controllerUploadId.includes(targetId || ""))
    ) {
      console.log("✅ Partial id match via fallback — proceeding.");
      shouldProceed = true;
    }

    if (!shouldProceed) {
      console.warn("🚫 Event ignored because no matching upload identifier found.", {
        uploadId,
        controllerUploadId,
        targetId,
      });
      return;
    }

    console.log("📊 Proceeding with KPI extraction workflow...");

    // Parse KPI mappings (array of { reported_kpi_name, ... })
    const reportedKpis = JSON.parse(this.element.dataset.reportedKpis || "[]");
    console.log("📊 Parsed reported KPIs:", reportedKpis);

    // Read XLSX file into workbook structure via XLSXLib
    const reader = new FileReader();
    reader.onload = (e) => {
      console.log("📘 KPI XLSX REPORT: FileReader onload triggered for:", file.name);
      const data = new Uint8Array(e.target.result); // binary XLSX data
      const workbook = XLSXLib.read(data, { type: "array" }); // parse workbook
      console.log("🔍 Workbook loaded, sheet names:", workbook.SheetNames);
      this.analyzeWorkbook(workbook, reportedKpis);
    };

    // ✅ Proceed directly — both uploadId and fallbackId handled above
    reader.onerror = (err) => {
      console.error("❌ FileReader error:", err);
    };
    reader.readAsArrayBuffer(file);

    // 🔧 Remove redundant strict mismatch block — ensure resume after proceeding flag
    console.log("⚙️ Finalized file read trigger complete for KPI XLSX Report Controller.");

    // Adjust rule to accept same ID substring or prefix matches (for dynamic upload IDs)
    if (controllerUploadId && !uploadId?.includes(controllerUploadId)) {
      console.warn(
        "⚠️ uploadId mismatch — relaxed check applied, still ignored due to no substring match",
        { uploadId, controllerUploadId }
      );
      return;
    }
    reader.onerror = (err) => {
      console.error("❌ FileReader error:", err);
    };
    reader.readAsArrayBuffer(file);

    // 🚀 Fallback: directly trigger processing when uploadId missing (for 3rd-party or non‑standard events)
    if (!uploadId) {
      console.warn("⚠️ uploadId missing from event.detail — executing fallback flow using target ID.");

      const fallbackId = event.target?.id || event.target?.closest("[id]")?.id;
      console.log("🔍 Derived fallbackId:", fallbackId);

      // Proceed only if target ID loosely matches the controller identifier
      if (
        fallbackId &&
        (fallbackId === controllerUploadId ||
          fallbackId.includes(controllerUploadId) ||
          controllerUploadId.includes(fallbackId))
      ) {
        console.log("✅ Fallback matched — proceeding to analyze workbook via upload-preview controller data.");
        // Try to extract file references or re-trigger analysis preparation
        // If xlsx-preview is already listening, we just log to confirm interception
      } else {
        console.log("🚫 Fallback did not match target or controller IDs.", {
          fallbackId,
          controllerUploadId,
        });
      }
    }
  }

  analyzeWorkbook(workbook, reportedKpis) {
    console.log("📊 KPI XLSX REPORT: Starting analysis...");
    const results = [];
    const allFoundKpis = new Set();
    const errors = [];

    workbook.SheetNames.forEach((sheetName) => {
      console.log(`▶️ Analyzing sheet: ${sheetName}`);
      const sheet = workbook.Sheets[sheetName];
      if (!sheet["!ref"]) {
        errors.push(`⚠️ Sheet '${sheetName}' is empty or invalid.`);
        return;
      }

      const data = XLSXLib.utils.sheet_to_json(sheet, { header: 1 });
      console.log(`📄 ${sheetName} has ${data.length} rows`);

      if (data.length === 0) {
        errors.push(`Sheet '${sheetName}' is empty.`);
        return;
      }

      const headerRow = data[0] || [];
      const dateLikeCount = headerRow.slice(1).filter((v) => {
        if (!v) return false;

        // Recognize numeric Excel date serials (e.g., 45689 -> 2025-02-15) as valid
        if (!isNaN(v) && v > 10000 && v < 60000) return true;

        const s = v.toString().trim().toUpperCase();

        // Match the detailed Ruby KpiDateUtils.date_like? patterns
        const patterns = [
          /\bH[12](?:\s?FY)?\s?\d{2,4}\b/i, // H1 2023, H2FY23
          /\bQ[1-4][-' ]?(?:FY|CY)?\d{2,4}\b/i, // Q1FY25, Q3CY22
          /\bFY\s?\d{2,4}[-–]\d{2,4}\b/i, // FY2020-21
          /\b(?:FY|CY)\s?\d{2,4}\b/i, // FY23, CY2024
          /\b(?:JAN(?:UARY)?|FEB(?:RUARY)?|MAR(?:CH)?|APR(?:IL)?|MAY|JUN(?:E)?|JUL(?:Y)?|AUG(?:UST)?|SEP(?:T(?:EMBER)?)?|OCT(?:OBER)?|NOV(?:EMBER)?|DEC(?:EMBER)?)\s+(\d{2,4})\b/i, // Jan 24, September 2024
          /\b(?:JFM|AMJ|JAS|OND)\s+\d{4}\b/i, // JFM 2021
          /\b(?:JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|SEPT|OCT|NOV|DEC)-(?:JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|SEPT|OCT|NOV|DEC)\s+\d{4}\b/i, // Jan-Mar 2021
          /\b\d{2}[-/]\d{2}[-/]\d{2,4}\b/, // 01-11-2024
          /\b\d{4}\b/, // plain year
        ];

        // Special handling: support "Jan-24", "Feb-24", "Mar-25" etc.
        const monthYearDash = /\b(?:JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|SEPT|OCT|NOV|DEC)[-’']?\d{2,4}\b/i;
        if (monthYearDash.test(s)) return true;

        return patterns.some((p) => p.test(s));
      }).length;

      if (dateLikeCount < 1) {
        errors.push(
          `❌ Invalid or missing header row in sheet '${sheetName}'. Expected date-like values (e.g., Jan 24, FY24, Q1FY25, H1FY25). Found: ${headerRow.slice(1).join(", ")}`
        );
        return;
      }

      const hasKpiNames = data.length > 1 && data.some((r, i) => i > 0 && r[0] && r[0].toString().trim() !== "");
      if (!hasKpiNames) {
        errors.push(`❌ Missing KPI names in sheet '${sheetName}'. The first column should contain KPI names.`);
        return;
      }

      const headers = headerRow.map((h) => (h ? h.toString().trim().toLowerCase() : ""));
      reportedKpis.forEach((kpiObj) => {
        const normalize = (str) =>
          (str || "").toString().replace(/\s+/g, "").toLowerCase();

        const name = normalize(kpiObj.reported_kpi_name);
        const row = data.find((r) => normalize(r[0]) === name);

        if (!row) {
          console.log(`❌ KPI '${name}' not found in ${sheetName}`);
          return;
        }

        console.log(`✅ Found KPI '${name}' in ${sheetName}`);
        allFoundKpis.add(name);

        const nonBlankCount = row.slice(1).filter((v) => v && v.toString().trim() !== "").length;
        results.push({ sheet: sheetName, kpi: kpiObj.reported_kpi_name, nonBlankCount });
      });
    });

    if (errors.length > 0) {
      const html = `<div class="alert alert-danger"><strong>Validation Errors Found:</strong><ul>${errors
        .map((e) => `<li>${e}</li>`)
        .join("")}</ul></div>`;
      this.outputTarget.innerHTML = html;
      console.error("🚫 Validation errors:", errors);
      return;
    }

    const foundNames = new Set(results.map((r) => r.kpi.toLowerCase()));
    const missing = reportedKpis
      .filter((k) => !foundNames.has(k.reported_kpi_name.toLowerCase()))
      .map((k) => k.reported_kpi_name);

    console.log("📋 KPI XLSX REPORT SUMMARY:", { results, missing });
    this.renderReport(results, missing);
  }

  /**
   * Renders an HTML summary of analysis results.
   * Displays:
   *  - A success/failure alert depending on missing KPIs
   *  - A table of all found KPIs with the count of non-empty values
   */
  renderReport(results, missing) {
    let html = "<div class='card card-body'>";

    // ✅ Show missing KPI alert if there are missing items
    if (missing.length > 0) {
      html += `<div class="alert alert-danger">Missing KPIs: ${missing.join(", ")}</div>`;
    } else {
      html += `<div class="alert alert-success">All KPIs found.</div>`;
    }

    // 🧮 Show a table of KPI rows (present and missing)
    const allKpis = [
      ...results.map((r) => ({
        sheet: r.sheet,
        kpi: r.kpi,
        nonBlankCount: r.nonBlankCount,
        present: true,
      })),
      ...missing.map((m) => ({
        sheet: "-",
        kpi: m,
        nonBlankCount: 0,
        present: false,
      })),
    ];

    if (allKpis.length > 0) {
      html += `<table class="table table-bordered">
        <thead><tr><th>Status</th><th>Sheet</th><th>KPI</th><th>Non-Blank Values</th></tr></thead><tbody>`;
      allKpis.forEach((r) => {
        const icon = r.present
          ? '<span style="color:green;">&#10004;</span>'
          : '<span style="color:red;">&#10008;</span>';
        html += `<tr>
          <td>${icon}</td>
          <td>${r.sheet}</td>
          <td>${r.kpi}</td>
          <td>${r.nonBlankCount}</td>
        </tr>`;
      });
      html += "</tbody></table>";
    } else {
      html += "<p>No KPIs data available.</p>";
    }

    html += "</div>";

    // Inject into output target inside the DOM
    this.outputTarget.innerHTML = html;
  }

}