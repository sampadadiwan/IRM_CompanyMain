import { Controller } from "@hotwired/stimulus";

// Attached to #kpi_validation_panel (kpi_reports/_validation_panel.html.erb), which the server
// re-renders after every workbook check. On each (re)connect it applies the submit guard from the
// server's error count — the browser never decides validity itself
// (docs/technical/kpi_portco_upload_validation_review.md §2.3 / §2.10).
export default class extends Controller {
  static values = {
    errors: Number,    // number of blocking errors in the current verdict
    checked: Boolean,  // whether a verdict exists at all
  };

  connect() {
    this.applyGuard();
  }

  errorsValueChanged() {
    this.applyGuard();
  }

  // Disables or re-enables the portco form's buttons from the server verdict:
  //   - blocking errors            → every [data-kpi-submit-guard] button disabled
  //   - no workbook checked yet    → only the "final" (Submit Report / Confirm) buttons disabled,
  //                                  Save Draft stays usable (§2.1 H — start guarded)
  //   - checked, no errors         → everything enabled
  // Only portco form buttons carry this attribute, so fund admin forms are unaffected.
  applyGuard() {
    const hasErrors = this.checkedValue && this.errorsValue > 0;
    document.querySelectorAll("[data-kpi-submit-guard]").forEach((el) => {
      const isFinal = el.dataset.kpiSubmitGuard === "final";
      el.disabled = hasErrors || (isFinal && !this.checkedValue);
    });
  }
}
