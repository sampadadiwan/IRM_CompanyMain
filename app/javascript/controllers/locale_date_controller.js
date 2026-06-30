import { Controller } from "@hotwired/stimulus"

// Keeps a locale-formatted display input, a hidden ISO submission input, and a
// transparent native <input type="date"> in sync.
// Clicking the display text input or the calendar icon both open the native picker.
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

    if (this.hasHiddenTarget) this.hiddenTarget.value = iso

    const [year, month, day] = iso.split("-")
    this.displayTarget.value = this.formatValue
      .replace("%d", day.padStart(2, "0"))
      .replace("%m", month.padStart(2, "0"))
      .replace("%Y", year)
  }

  // Called when the user types directly into the display input (or a test fills it in).
  // Accepts both locale-formatted strings and ISO "YYYY-MM-DD" so Capybara fill_in works.
  inputChanged() {
    const raw = this.displayTarget.value.trim()
    if (!raw) {
      if (this.hasHiddenTarget) this.hiddenTarget.value = ""
      // Clear the picker so a subsequent calendar open doesn't restore the old date
      if (this.hasPickerTarget) this.pickerTarget.value = ""
      return
    }
    const iso = this.parseToIso(raw)
    if (!iso) return
    if (this.hasHiddenTarget) this.hiddenTarget.value = iso
    if (this.hasPickerTarget)  this.pickerTarget.value  = iso
  }

  // Parses a date string to ISO "YYYY-MM-DD".
  // Handles ISO input, Ruby datetime strings (Time#to_s), and locale-formatted input.
  parseToIso(raw) {
    // Ruby Time#to_s / ActiveSupport datetime prefix: "2024-03-02 00:00:00 +0530" or exact ISO
    const dtMatch = raw.match(/^(\d{4})-(\d{2})-(\d{2})/)
    if (dtMatch) return `${dtMatch[1]}-${dtMatch[2]}-${dtMatch[3]}`

    const fmt = this.formatValue
    // Determine the positional order of day/month/year tokens in the format string
    const order = [
      { key: "d", pos: fmt.indexOf("%d") },
      { key: "m", pos: fmt.indexOf("%m") },
      { key: "y", pos: fmt.indexOf("%Y") }
    ].sort((a, b) => a.pos - b.pos).map(x => x.key)

    // Escape regex metacharacters in separator characters (e.g. '.' in %d.%m.%Y)
    // before substituting the date-part capture groups.
    const escaped = fmt.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
    const pattern = escaped
      .replace("%d", "(\\d{1,2})")
      .replace("%m", "(\\d{1,2})")
      .replace("%Y", "(\\d{4})")
    const match = raw.match(new RegExp("^" + pattern + "$"))
    if (!match) return null

    const parsed = {}
    order.forEach((key, i) => { parsed[key] = match[i + 1].padStart(2, "0") })
    return `${parsed.y}-${parsed.m}-${parsed.d}`
  }
}
