import { Controller } from "@hotwired/stimulus"
import { initSelect2 } from "custom/select2_handler"

// Multi-select field picker for the "Field History" tab of the AuditTrail
// component (app/packs/core/components/audit_trail.html.erb) — shows/hides
// table rows depending on which attributes are selected in the <select multiple>.
export default class extends Controller {
  static targets = ["picker", "row"]

  connect() {
    initSelect2(this.element)

    // Select2 mutates the underlying <select> and fires jQuery's own 'change'
    // event, not a native DOM one — a plain `data-action="change->..."` only
    // catches the native kind, so removing a tag (select2:unselect) or
    // clearing all never reached this controller. Bind through jQuery instead
    // so add, remove, and clear are all covered.
    $(this.pickerTarget).on("change", () => this.filter())
  }

  disconnect() {
    $(this.pickerTarget).off("change")
  }

  // The tab starts hidden (Timeline is the default tab), and Select2 measures
  // width off the DOM at init time — a `display: none` ancestor makes that
  // measurement come back 0. Re-run once the tab is actually shown; initSelect2
  // no-ops on an element it already initialized.
  reinitOnShow(event) {
    if (event.target.dataset.bsTarget !== `#${this.element.id}`) return

    initSelect2(this.element)
  }

  filter() {
    const selected = Array.from(this.pickerTarget.selectedOptions).map((o) => o.value)

    this.rowTargets.forEach((row) => {
      row.style.display = selected.includes(row.dataset.fieldKey) ? "" : "none"
    })
  }

  clearAll() {
    $(this.pickerTarget).val(null).trigger("change")
  }
}
