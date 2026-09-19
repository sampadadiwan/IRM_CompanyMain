import { Controller } from "@hotwired/stimulus"
import { parseLocaleDate } from "custom/locale_date_format"

// Keeps a locale-formatted display input, a hidden ISO submission input, and a
// transparent native <input type="date"> in sync.
// The display input is a plain text field the user types into; the calendar icon
// is the only thing that opens the native picker (clicking the text field must not,
// or the popup steals focus and the field becomes effectively calendar-only).
export default class extends Controller {
  static targets = ["display", "picker", "hidden"]
  static values  = { format: String }

  // Opens the native browser date picker programmatically
  openPicker() {
    try {
      this.pickerTarget.showPicker()
    } catch (_e) {
      // showPicker() requires a user gesture — should always be satisfied here
    }
  }

  // Called when the user selects a date from the native calendar
  pickerChanged() {
    const iso = this.pickerTarget.value  // "YYYY-MM-DD"
    if (!iso) return

    this.commit(iso)
    this.displayTarget.value = this.formatIso(iso)
    this.displayTarget.classList.remove("is-invalid")
  }

  // Called when the user types directly into the display input (or a test fills it in).
  // Accepts both locale-formatted strings and ISO "YYYY-MM-DD" so Capybara fill_in works.
  inputChanged() {
    // A half-typed date is not a value yet, and neither is an unparseable one. Either
    // way the previously committed date has to be cleared: leaving it behind would
    // submit a date the user can no longer see (a filter silently applying a stale bound).
    const iso = this.parseToIso(this.displayTarget.value)
    this.commit(iso || "")
    // Validity is only signalled on blur — flagging mid-keystroke would mark every
    // partially-typed date red.
    if (iso) this.displayTarget.classList.remove("is-invalid")
  }

  // On blur, rewrite a recognised date into the canonical locale format (so "1.2.2026"
  // becomes "01/02/2026") and flag anything left unparseable.
  inputBlurred() {
    const raw = this.displayTarget.value.trim()
    if (!raw) {
      this.displayTarget.classList.remove("is-invalid")
      return
    }
    const iso = this.parseToIso(raw)
    if (iso) {
      this.displayTarget.value = this.formatIso(iso)
      this.displayTarget.classList.remove("is-invalid")
    } else {
      this.displayTarget.classList.add("is-invalid")
    }
  }

  // Writes the committed ISO value to both the submitted hidden input and the native
  // picker, so reopening the calendar shows what the text field currently says.
  // Fires `change` on the hidden input because that is the element filter forms bind
  // their auto-refresh to — without it, a typed date never triggers the refresh that
  // an icon-picked one does.
  commit(iso) {
    if (this.hasPickerTarget) this.pickerTarget.value = iso
    if (!this.hasHiddenTarget) return
    if (this.hiddenTarget.value === iso) return
    this.hiddenTarget.value = iso
    this.hiddenTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  parseToIso(raw) {
    return parseLocaleDate(raw, this.formatValue)
  }

  // Renders ISO "YYYY-MM-DD" in the locale's strftime format.
  formatIso(iso) {
    const [year, month, day] = iso.split("-")
    return this.formatValue
      .replace("%d", day.padStart(2, "0"))
      .replace("%m", month.padStart(2, "0"))
      .replace("%Y", year)
  }
}
