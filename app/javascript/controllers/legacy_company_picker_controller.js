import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="legacy-company-picker"
//
// The company step of the legacy bulk generate flow. "Next" stays disabled until at least one
// portfolio company is chosen in the list. The list sits in a Turbo frame that Preview reloads, and
// it is a select2, so the check runs on select2/change events and again after every frame load.
export default class extends Controller {
  static targets = ["next"]

  connect() {
    this.update = this.update.bind(this)
    $(this.element).on(
      "change.companyPicker select2:select.companyPicker select2:unselect.companyPicker select2:clear.companyPicker",
      "select[name='portfolio_company_ids[]']",
      this.update
    )
    this.element.addEventListener("turbo:frame-load", this.update)
    this.update()
  }

  disconnect() {
    $(this.element).off(".companyPicker")
    this.element.removeEventListener("turbo:frame-load", this.update)
  }

  update() {
    const select = this.element.querySelector("select[name='portfolio_company_ids[]']")
    const chosen = select ? select.selectedOptions.length > 0 : false
    this.nextTarget.disabled = !chosen
  }
}
