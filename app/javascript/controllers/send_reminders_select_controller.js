// Syncs a Select2 multi-select with a table of checkboxes for the Send
// Reminders panel. Selecting/deselecting a company in Select2 checks/unchecks
// the corresponding table row, and vice versa.
//
// Select2 fires jQuery events (not native DOM events), so we bind via
// jQuery in connect() rather than Stimulus data-action attributes.
//
// @see _actions.html.erb for the panel markup
// @see PortfolioCompanyDashboardController#send_reminders for server-side handling
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "checkbox", "selectAll", "row", "submitBtn"]

  // Binds the jQuery change event on the Select2 element so selections
  // sync to table checkboxes. Native DOM events don't fire for Select2.
  connect() {
    this.$select = $(this.selectTarget)
    this.$select.on("change.sendReminders", () => this.syncFromSelect())
  }

  // Unbinds the jQuery event listener to prevent memory leaks.
  disconnect() {
    if (this.$select) {
      this.$select.off("change.sendReminders")
    }
  }

  // Called when the Select2 dropdown changes. Syncs table checkboxes to
  // match the current Select2 selection.
  syncFromSelect() {
    const selected = new Set(
      Array.from(this.selectTarget.selectedOptions).map(opt => opt.value)
    )
    this.checkboxTargets.forEach(cb => {
      cb.checked = selected.has(cb.value)
    })
    this.refreshSelectAll()
  }

  // Called when a table checkbox changes. Syncs the Select2 dropdown to
  // match the current table selection.
  syncFromTable() {
    const selectedValues = this.checkboxTargets
      .filter(cb => cb.checked)
      .map(cb => cb.value)

    // Update Select2 value without triggering the change event back
    // (would cause an infinite loop). Use triggerChange: false workaround.
    this.$select.off("change.sendReminders")
    this.$select.val(selectedValues).trigger("change")
    this.$select.on("change.sendReminders", () => this.syncFromSelect())
    this.refreshSelectAll()
  }

  // Toggles all table checkboxes and syncs Select2 to match.
  toggleAll() {
    const checked = this.selectAllTarget.checked
    this.checkboxTargets.forEach(cb => { cb.checked = checked })
    this.syncFromTable()
  }

  // Updates the select-all checkbox state and submit button based on
  // current table selections.
  //
  // @private
  refreshSelectAll() {
    const total = this.checkboxTargets.length
    const selected = this.checkboxTargets.filter(cb => cb.checked).length
    this.selectAllTarget.checked = selected === total
    this.selectAllTarget.indeterminate = selected > 0 && selected < total
    this.submitBtnTarget.disabled = selected === 0
  }
}
