import { Controller } from "@hotwired/stimulus"

// Per-deal analytics stat configurator.
// Each row chooses a stat field and an editable title.
// All rows are serialized to JSON in a hidden field on every change.
export default class extends Controller {
  static targets = ["rows", "template", "row", "jsonField"]

  connect() {
    // Rows can already be present on load (editing a deal with saved stats),
    // so existing rows need listeners wired up before any templated rows are added.
    this.rowTargets.forEach(row => this._listenRow(row))
    this.updateJson()
  }

  addRow() {
    // Rows are cloned from a <template> rather than built as an HTML string so the
    // markup (including the field <select> options) stays in the view/ERB, not duplicated in JS.
    const clone = this.templateTarget.content.cloneNode(true)
    this.rowsTarget.appendChild(clone)
    this._listenRow(this.rowTargets[this.rowTargets.length - 1])
    this.updateJson()
  }

  removeRow(event) {
    event.currentTarget.closest("[data-deal-analytics-stats-target='row']").remove()
    this.updateJson()
  }

  // The form only submits a single hidden field (see jsonField), so every add/remove/edit
  // re-serializes all rows into it. Rows without a chosen stat field are dropped since an
  // empty selection isn't a valid analytics stat and would otherwise fail Deal#normalize_analytics_stats.
  updateJson() {
    const stats = this.rowTargets
      .map(row => ({
        field: row.querySelector("[data-field='field']")?.value || "",
        label: row.querySelector("[data-field='label']")?.value || ""
      }))
      .filter(item => item.field)

    this.jsonFieldTarget.value = JSON.stringify(stats)
  }

  // Delegating change/input from each row (rather than one listener on the container)
  // keeps things simple since rows are added/removed dynamically and this is called
  // explicitly whenever a row is inserted.
  _listenRow(row) {
    row.querySelectorAll("select, input").forEach(el => {
      el.addEventListener("change", () => this.updateJson())
      el.addEventListener("input", () => this.updateJson())
    })
  }
}
