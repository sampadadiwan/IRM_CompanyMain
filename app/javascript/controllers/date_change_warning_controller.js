import { Controller } from "@hotwired/stimulus"
import { formatLocaleDate } from "custom/locale_date_format"

// Confirm-gate for a date field whose edit cascades to child records (call_date -> every
// capital_remittance's remittance_date, distribution_date -> every capital_distribution_payment's
// payment_date - see docs/modules/funds/call_and_distribution_date_cascade_plan.md). The form submits
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
    // inputTarget is the locale-date widget's HIDDEN input, so its value is ISO.
    // Showing it raw would put "2026-02-01" in front of a user whose every other
    // date reads dd/mm/yyyy.
    if (this.hasNewDateTarget) {
      this.newDateTarget.textContent = this.displayValue(this.inputTarget.value)
    }
    bootstrap.Modal.getOrCreateInstance(this.modalTarget).show()
  }

  confirm() {
    this.confirmed = true
    bootstrap.Modal.getOrCreateInstance(this.modalTarget).hide()
    this.element.querySelector("form").requestSubmit()
  }

  cancel() {
    this.restoreOriginalDate()
    bootstrap.Modal.getOrCreateInstance(this.modalTarget).hide()
  }

  // Restoring inputTarget alone is not enough: it is the hidden ISO input of a
  // locale-date widget, so the visible field would keep showing the date the user
  // typed while the form submitted the original one. Drive the display input and
  // let locale-date resync the hidden input and the native picker from it.
  restoreOriginalDate() {
    this.inputTarget.value = this.originalValueValue

    const widget = this.localeDateWidget()
    if (!widget) return
    const display = widget.querySelector("[data-locale-date-target='display']")
    if (!display) return

    display.value = this.displayValue(this.originalValueValue)
    display.dispatchEvent(new Event("input", { bubbles: true }))
  }

  // ISO -> the locale format this widget renders in. Falls back to the raw value
  // for a plain (non-locale-date) input, and to "" for a record with no date set.
  displayValue(iso) {
    const widget = this.localeDateWidget()
    if (!widget) return iso
    return formatLocaleDate(iso, widget.dataset.localeDateFormatValue)
  }

  localeDateWidget() {
    return this.inputTarget.closest("[data-controller~='locale-date']")
  }
}
