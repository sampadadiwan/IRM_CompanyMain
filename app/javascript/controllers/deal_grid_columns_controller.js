import { Controller } from "@hotwired/stimulus"

// Per-deal grid column configurator.
// Each row chooses a field, optional label, and position (Start / End).
// All rows are serialized to JSON in a hidden field on every change.
export default class extends Controller {
  static targets = ["rows", "template", "row", "jsonField"]

  connect() {
    // Attach change/input listeners to server-rendered existing rows
    this.rowTargets.forEach(row => this._listenRow(row))
    this.updateJson()
  }

  addRow() {
    const clone = this.templateTarget.content.cloneNode(true)
    // The cloned fragment doesn't have the target attribute accessible yet;
    // grab the real element after inserting it.
    this.rowsTarget.appendChild(clone)
    this._listenRow(this.rowTargets[this.rowTargets.length - 1])
    this.updateJson()
  }

  removeRow(event) {
    event.currentTarget.closest("[data-deal-grid-columns-target='row']").remove()
    this.updateJson()
  }

  updateJson() {
    const cols = this.rowTargets
      .map(row => ({
        field:    row.querySelector("[data-field='field']")?.value    || "",
        label:    row.querySelector("[data-field='label']")?.value    || "",
        position: row.querySelector("[data-field='position']")?.value || "end"
      }))
      .filter(c => c.field)   // discard rows with no field selected

    this.jsonFieldTarget.value = JSON.stringify(cols)
  }

  _listenRow(row) {
    row.querySelectorAll("select, input").forEach(el => {
      el.addEventListener("change", () => this.updateJson())
      el.addEventListener("input",  () => this.updateJson())
    })
  }
}
