import { Controller } from "@hotwired/stimulus"

// Confirm-gate for a date field whose edit cascades to child records (call_date -> every
// capital_remittance's remittance_date, distribution_date -> every capital_distribution_payment's
// payment_date - see docs/technical/call_and_distribution_date_cascade_plan.md). The form submits
// normally unless the date field actually changed; if it did, submission is intercepted and an
// "Immediate Actions" warning modal is shown. Only the modal's own Confirm button lets the
// submit through.
export default class extends Controller {
  static targets = ["input", "modal", "newDate"]
  static values = { originalValue: String }

  connect() {
    this.confirmed = false
  }

  interceptSubmit(event) {
    if (this.confirmed) return
    if (this.inputTarget.value === this.originalValueValue) return

    event.preventDefault()
    if (this.hasNewDateTarget) this.newDateTarget.textContent = this.inputTarget.value
    bootstrap.Modal.getOrCreateInstance(this.modalTarget).show()
  }

  confirm() {
    this.confirmed = true
    bootstrap.Modal.getOrCreateInstance(this.modalTarget).hide()
    this.element.querySelector("form").requestSubmit()
  }

  cancel() {
    this.inputTarget.value = this.originalValueValue
    bootstrap.Modal.getOrCreateInstance(this.modalTarget).hide()
  }
}
