// Stimulus controller for the NDA Settings modal form. Handles client-side
// toggle of conditional fields without server round-trips.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["fields", "fixedPeriod", "specificDate"]
  static values = { enabled: Boolean }

  // Show/hide the config fields based on the Require NDA toggle.
  toggleEnabled(event) {
    const enabled = event.target.value === "true"
    this.enabledValue = enabled

    if (this.hasFieldsTarget) {
      this.fieldsTarget.classList.toggle("d-none", !enabled)
    }
  }

  // Show/hide validity sub-fields based on the selected validity type.
  toggleValidity(event) {
    const type = event.target.value

    if (this.hasFixedPeriodTarget) {
      this.fixedPeriodTarget.classList.toggle("d-none", type !== "fixed_period")
    }
    if (this.hasSpecificDateTarget) {
      this.specificDateTarget.classList.toggle("d-none", type !== "specific_date")
    }
  }
}
