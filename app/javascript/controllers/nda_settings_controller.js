// Stimulus controller for the NDA Settings modal form. Handles client-side
// toggle of conditional fields without server round-trips.
// Changed: Added versionWarning target and upload:complete listener (Module 4).
// Why: When a GP selects a new NDA PDF via Uppy, the warning banner shows the
//   count of accepted investors who will need to re-accept after the version bump.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["fields", "fixedPeriod", "specificDate", "versionWarning"]
  static values = { enabled: Boolean }

  connect() {
    this.handleUploadComplete = this.showVersionWarning.bind(this)
    this.element.addEventListener("upload:complete", this.handleUploadComplete)
  }

  disconnect() {
    this.element.removeEventListener("upload:complete", this.handleUploadComplete)
  }

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

  /**
   * Shows the version bump warning banner when a new PDF is uploaded via Uppy.
   * Listens for the bubbling upload:complete event dispatched by single_upload_controller.
   * Only shows the banner when there are accepted investors who would be affected.
   */
  showVersionWarning() {
    if (!this.hasVersionWarningTarget) return

    const count = parseInt(this.versionWarningTarget.dataset.acceptedCount, 10) || 0
    if (count > 0) {
      this.versionWarningTarget.classList.remove("d-none")
    }
  }
}
