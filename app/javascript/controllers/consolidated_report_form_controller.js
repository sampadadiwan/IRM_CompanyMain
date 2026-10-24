import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="consolidated-report-form"
// A consolidated report has no sections, so the sections block is hidden (and its fields disabled,
// so nothing from it is submitted) while the Consolidated box is ticked.
export default class extends Controller {
  static targets = ["checkbox", "sections"]

  connect() {
    this.toggle()
  }

  toggle() {
    const consolidated = this.checkboxTarget.checked
    this.sectionsTarget.hidden = consolidated
    this.sectionsTarget.querySelectorAll("input, textarea, select").forEach(el => { el.disabled = consolidated })
  }
}
