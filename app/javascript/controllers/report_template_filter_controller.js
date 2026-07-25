import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="report-template-filter"
//
// Scopes the report template <select> to the currently selected Portfolio Report.
// Each template <option> carries a data-report-id; when the Report changes (or on load)
// we hide the templates that don't belong to it and select the first one that does, so
// the template shown is always a valid template of the chosen report.
export default class extends Controller {
  static targets = ["report", "template"]

  connect() {
    this.filter()
  }

  filter() {
    const reportId = this.reportTarget.value
    let firstMatch = null

    Array.from(this.templateTarget.options).forEach(option => {
      const matches = option.dataset.reportId === reportId
      option.hidden = !matches
      option.disabled = !matches
      if (matches && firstMatch === null) firstMatch = option
    })

    // If the currently selected template no longer belongs to the chosen report,
    // fall back to the first template that does (or clear it when none exist).
    const current = this.templateTarget.selectedOptions[0]
    if (!current || current.hidden) {
      this.templateTarget.value = firstMatch ? firstMatch.value : ""
    }
  }
}
