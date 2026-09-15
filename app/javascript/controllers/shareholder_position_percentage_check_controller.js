import { Controller } from "@hotwired/stimulus";

// Fully Dilluted % totals + duplicate row checks for ShareholderPosition uploads - display only,
// all rules live server-side (ImportShareholderPosition#percentage_total_errors and
// #duplicate_row_errors, reached via ShareholderPositionUploadsController#validate_upload /
// ValidateShareholderPositionPercentages). Entirely separate from the generic xlsx-preview
// partial/controller (which only checks headers, for every import type) so that shared code is
// never touched by these ShareholderPosition-specific rules - see
// _shareholder_position_percentage_check.html.erb.
//
//   1. listens for the `upload:complete` event the upload widget fires after Uppy finishes,
//   2. POSTs the uploaded file reference (Shrine cached-file JSON) - or the File itself as a
//      fallback - to the validate_upload endpoint,
//   3. renders the JSON result into its own status panel,
//   4. blocks form submission itself by intercepting the form's submit event, independently of
//      the header-check's own submit guard (data-xlsx-submit-guard) - so this controller never
//      has to fight over the Save button's disabled state with xlsx_preview_controller.js.
export default class extends Controller {
  static targets = ["status"];
  static values = { url: String };

  connect() {
    this.blocked = false;
    this.handleUploadBound = this.handleUpload.bind(this);
    document.addEventListener("upload:complete", this.handleUploadBound);

    this.form = this.element.closest("form");
    this.handleSubmitBound = this.handleSubmit.bind(this);
    this.form?.addEventListener("submit", this.handleSubmitBound);
  }

  disconnect() {
    document.removeEventListener("upload:complete", this.handleUploadBound);
    this.form?.removeEventListener("submit", this.handleSubmitBound);
  }

  handleSubmit(event) {
    if (!this.blocked) return;
    event.preventDefault();
    event.stopImmediatePropagation();
  }

  handleUpload(event) {
    if (!this.urlValue) return;
    const { file, uploadedData } = event.detail || {};

    const body = new FormData();
    body.append("import_type", "ShareholderPosition");
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

  async post(body) {
    if (this.hasStatusTarget) {
      this.statusTarget.innerHTML = '<div class="alert alert-info">Checking Fully Dilluted % totals and duplicate rows...</div>';
    }

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "",
        },
        body,
        credentials: "same-origin",
      });
      const result = await response.json();
      this.blocked = !result.ok;
      if (this.hasStatusTarget) {
        const errors = (result.errors || []).map((msg) => `<div>${this.escapeHtml(msg)}</div>`).join("");
        this.statusTarget.innerHTML = result.ok
          ? '<div class="alert alert-success">Fully Dilluted % totals 100% for every Portfolio Company/Stakeholder + As Of round, and no duplicate rows were found.</div>'
          : `<div class="alert alert-danger">${errors}<div>Please fix and re-upload before saving.</div></div>`;
      }
    } catch (err) {
      this.blocked = true;
      if (this.hasStatusTarget) {
        this.statusTarget.innerHTML = `<div class="alert alert-danger">Could not run upload checks: ${this.escapeHtml(err.message)}</div>`;
      }
    }
  }

  escapeHtml(unsafe) {
    if (unsafe === null || unsafe === undefined) return "";
    return String(unsafe)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }
}
