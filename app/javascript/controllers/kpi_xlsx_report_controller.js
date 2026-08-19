import { Controller } from "@hotwired/stimulus";

// KPI workbook check — display only.
//
// All validation rules live on the server (KpiWorkbookReader#validate, reached via
// KpiReportsController#validate_upload). This controller:
//   1. listens for the `upload:complete` event the file-upload component fires after Uppy finishes,
//   2. POSTs the uploaded file reference (Shrine cached-file JSON) — or the File itself as a
//      fallback — to the validate_upload endpoint,
//   3. renders the turbo_stream response, which replaces #kpi_validation_panel.
// The panel's own controller (kpi-validation-panel) toggles the submit guard from the server's
// error count. No regexes, no counting, no rules here — by design
// (docs/technical/kpi_portco_upload_validation_review.md §2.3).
export default class extends Controller {
  static targets = ["spinner"];
  static values = {
    url: String,          // validate_upload path (with signed_id for magic-link users)
    hasDocument: Boolean, // a KPIs document is already attached to the report
    hasVerdict: Boolean,  // a stored verdict was rendered server-side on page load
    persisted: Boolean,   // false on the New page — the report context is sent from the form fields
  };

  connect() {
    this.handleUploadBound = this.handleUpload.bind(this);
    document.addEventListener("upload:complete", this.handleUploadBound);

    // A document exists but nothing has been checked yet (e.g. attached before this feature) —
    // ask the server for a verdict so the panel and guard reflect reality on load.
    if (this.urlValue && this.hasDocumentValue && !this.hasVerdictValue) {
      this.post(new FormData());
    }
  }

  disconnect() {
    document.removeEventListener("upload:complete", this.handleUploadBound);
  }

  // "Re-check file" button — validates the already-attached KPIs document again.
  recheck() {
    if (!this.urlValue) return;
    this.post(new FormData());
  }

  handleUpload(event) {
    const { file, uploadId, uploadedData } = event.detail || {};
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
    if (!this.urlValue) return;

    const body = new FormData();
    this.appendFormContext(body);
    if (uploadedData) {
      // Normal path: Uppy already put the file in the Shrine cache; send the reference only.
      body.append("file_data", uploadedData);
    } else if (file) {
      // Fallback (tests / upload libs without cached data): send the bytes themselves.
      body.append("file", file, file.name);
    } else {
      return;
    }
    this.post(body);
  }

  // On the New page the report is not saved yet: send the form's portfolio company / as_of / period /
  // tag along so the server can build the same context the import will later use.
  appendFormContext(body) {
    if (this.persistedValue) return;
    const form = document.getElementById("kpi-report-form");
    if (!form) return;
    ["portfolio_company_id", "as_of", "period", "tag_list"].forEach((name) => {
      // The form renders a hidden text field AND a visible select for portfolio_company_id — prefer
      // the visible control (what the user actually chose), then fall back to any field of that name.
      const el = form.querySelector(`select[name="kpi_report[${name}]"]`) || form.querySelector(`[name="kpi_report[${name}]"]`);
      if (el && el.value !== undefined && el.value !== "") body.append(`kpi_report[${name}]`, el.value);
    });
  }

  async post(body) {
    this.showSpinner(true);
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          Accept: "text/vnd.turbo-stream.html",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "",
        },
        body,
        credentials: "same-origin",
      });
      const html = await response.text();
      if (response.ok && window.Turbo) {
        window.Turbo.renderStreamMessage(html);
      } else {
        this.renderFailure(`The workbook check could not be completed (HTTP ${response.status}). Please try again.`);
      }
    } catch (err) {
      this.renderFailure(`The workbook check could not be completed: ${err.message}`);
    } finally {
      this.showSpinner(false);
    }
  }

  // Network/server failure: show a message and keep Submit blocked — an unchecked file must not go through.
  renderFailure(message) {
    const panel = document.getElementById("kpi_validation_panel");
    if (!panel) return;
    panel.innerHTML = `<div class="alert alert-danger mb-0">${message}</div>`;
    // Mark as "checked with 1 error" so kpi_validation_panel_controller keeps every button disabled.
    panel.dataset.kpiValidationPanelCheckedValue = "true";
    panel.dataset.kpiValidationPanelErrorsValue = "1";
    document.querySelectorAll("[data-kpi-submit-guard]").forEach((el) => { el.disabled = true; });
  }

  showSpinner(on) {
    if (this.hasSpinnerTarget) this.spinnerTarget.classList.toggle("d-none", !on);
  }
}
