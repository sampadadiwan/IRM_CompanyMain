// Manages the Run Validation target selectors — builds a confirmation label
// from the Select2 multi-selects (tags, sectors, companies) and shows a
// dynamic confirmation dialog before form submission.
//
// @see _actions.html.erb for the form markup
// @see PortfolioCompanyDashboardController#run_validation for server-side handling
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { total: Number }

  // Builds a human-readable label describing the current target selection.
  // Reads selected values from the Select2 multi-selects to summarize
  // what will be validated in the confirmation dialog.
  //
  // @return {string} e.g. "all 12 portfolio companies" or "3 companies, tagged SaaS"
  targetLabel() {
    const parts = []

    const tags = this.selectedValues("target_tags[]")
    if (tags.length > 0) parts.push(`tagged ${tags.join(", ")}`)

    const sectors = this.selectedValues("target_sectors[]")
    if (sectors.length > 0) parts.push(`in sectors ${sectors.join(", ")}`)

    const companies = this.selectedValues("target_ids[]")
    if (companies.length > 0) parts.push(`${companies.length} selected ${companies.length === 1 ? "company" : "companies"}`)

    if (parts.length === 0) return `all ${this.totalValue} portfolio companies`
    return parts.join(", ")
  }

  // Shows a dynamic confirmation dialog before allowing form submission.
  // Includes the reminders toggle state so the FM knows whether reminder
  // emails will be sent as part of this validation run.
  //
  // @param {Event} event - the click event from the submit button
  confirmAndSubmit(event) {
    const sendReminders = this.element.querySelector("#send_reminders_toggle")
    const reminderNote = sendReminders?.checked
      ? "\n\nReminders WILL be sent to companies with missing items."
      : "\n\nReminders will NOT be sent."
    if (!confirm(`Run validation on ${this.targetLabel()}?${reminderNote}`)) {
      event.preventDefault()
    }
  }

  // Reads selected option values from a Select2 multi-select by field name.
  //
  // @param {string} name - the form field name (e.g. "target_tags[]")
  // @return {string[]} array of selected values
  selectedValues(name) {
    const select = this.element.querySelector(`[name="${name}"]`)
    if (!select) return []
    return Array.from(select.selectedOptions).map(opt => opt.value).filter(Boolean)
  }
}
