// Stimulus controller for the NDA Settings modal form. Handles client-side
// toggle of conditional fields without server round-trips.
// Changed: Added versionWarning target and upload:complete listener (Module 4).
// Why: When a GP selects a new NDA PDF via Uppy, the warning banner shows the
//   count of accepted investors who will need to re-accept after the version bump.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["fields", "fixedPeriod", "specificDate", "versionWarning", "currentFile", "currentFileName"]
  static values = { enabled: Boolean }

  // Changed: Module 9 — removed manual addEventListener for upload:complete.
  // Why: Replaced with Stimulus data-action on the form element
  //   (upload:complete->nda-settings#showVersionWarning) for reliable event binding.

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

  // Changed: Module 4 — shows version bump warning when a new PDF is uploaded.
  // Changed: Module 9 — also updates the "Current" filename display with the new file.
  // Why: GP needs immediate feedback showing which file they just uploaded, without
  //   waiting for the form to save. The filename link is replaced with plain text
  //   (no download URL yet — file is only cached on S3, not persisted).
  showVersionWarning(event) {
    if (this.hasVersionWarningTarget) {
      const count = parseInt(this.versionWarningTarget.dataset.acceptedCount, 10) || 0
      if (count > 0) {
        this.versionWarningTarget.classList.remove("d-none")
      }
    }

    const file = event?.detail?.file
    if (file && this.hasCurrentFileNameTarget) {
      this.currentFileNameTarget.textContent = file.name
      if (this.hasCurrentFileTarget) {
        this.currentFileTarget.classList.remove("d-none")
      }
    }
  }
}
