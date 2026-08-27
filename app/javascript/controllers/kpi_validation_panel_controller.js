import { Controller } from "@hotwired/stimulus";

// Attached to #kpi_validation_panel (kpi_reports/_validation_panel.html.erb), which the server
// re-renders after every workbook check. On each (re)connect it applies the submit guard from the
// server's error count — the browser never decides validity itself
// (docs/technical/kpi_portco_upload_validation_review.md §2.3 / §2.10).
export default class extends Controller {
  static values = {
    errors: Number,          // number of blocking errors in the current verdict
    checked: Boolean,        // whether a verdict exists at all
    warningsAcked: Boolean,  // true once every warning checkbox is ticked (or there are none)
  };
  static targets = ["warningCheckbox", "ackAll", "ackCount"];

  connect() {
    this.refreshAckState();
    this.applyGuard();
  }

  errorsValueChanged() {
    this.applyGuard();
  }

  warningsAckedValueChanged() {
    this.applyGuard();
  }

  // "Acknowledge all" checkbox toggled — check/uncheck every individual warning to match.
  toggleAll(event) {
    const checked = event.target.checked;
    this.warningCheckboxTargets.forEach((cb) => { cb.checked = checked; });
    this.refreshAckState();
  }

  // A single warning checkbox toggled.
  toggleOne() {
    this.refreshAckState();
  }

  // Recomputes the "acknowledge all" checkbox state, the progress caption, and whether every
  // warning has been ticked — each upload/re-check re-renders this panel from scratch, so a new
  // set of warnings always starts unacknowledged again.
  refreshAckState() {
    const total = this.warningCheckboxTargets.length;
    const ackedCount = this.warningCheckboxTargets.filter((cb) => cb.checked).length;

    if (this.hasAckAllTarget) {
      this.ackAllTarget.checked = total > 0 && ackedCount === total;
      this.ackAllTarget.indeterminate = ackedCount > 0 && ackedCount < total;
    }
    if (this.hasAckCountTarget) {
      this.ackCountTarget.textContent = total ? `${ackedCount} of ${total} acknowledged` : "";
    }
    this.warningsAckedValue = total === 0 || ackedCount === total;
  }

  // Disables or re-enables the portco form's buttons from the server verdict:
  //   - blocking errors                 → every [data-kpi-submit-guard] button disabled
  //   - no workbook checked yet         → only the "final" (Submit Report / Confirm) buttons disabled,
  //                                       Save Draft stays usable (§2.1 H — start guarded)
  //   - checked, unacknowledged warnings → "final" buttons stay disabled until every warning is ticked
  //   - checked, no errors, all acked   → everything enabled
  // Only portco form buttons carry this attribute, so fund admin forms are unaffected.
  applyGuard() {
    const hasErrors = this.checkedValue && this.errorsValue > 0;
    document.querySelectorAll("[data-kpi-submit-guard]").forEach((el) => {
      const isFinal = el.dataset.kpiSubmitGuard === "final";
      el.disabled = hasErrors || (isFinal && (!this.checkedValue || !this.warningsAckedValue));
    });
  }
}
