import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="task-recurrence"
export default class extends Controller {
  static targets = ["advancedSection", "recurrenceFields", "recurrenceToggle"]
  static values = { advancedVisible: Boolean }

  toggleAdvanced(event) {
    if (event) event.preventDefault()
    this.advancedVisibleValue = !this.advancedVisibleValue
  }

  advancedVisibleValueChanged() {
    if (!this.hasAdvancedSectionTarget) return

    if (this.advancedVisibleValue) {
      this.advancedSectionTarget.classList.remove("d-none")
    } else {
      this.advancedSectionTarget.classList.add("d-none")
    }

    // Update button text if it exists
    const btn = this.element.querySelector('[data-action*="task-recurrence#toggleAdvanced"]')
    if (btn) {
      btn.innerText = this.advancedVisibleValue ? "Hide Advanced Options" : "Show Advanced Options"
    }
  }

  toggleRecurrence(event) {
    if (this.recurrenceToggleTarget.checked) {
      this.recurrenceFieldsTarget.classList.remove("d-none")
    } else {
      this.recurrenceFieldsTarget.classList.add("d-none")
    }
  }
}
