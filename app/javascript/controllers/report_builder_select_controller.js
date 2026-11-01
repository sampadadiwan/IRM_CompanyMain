import { Controller } from "@hotwired/stimulus"

// The column picker of the Report Builder (builder Columns tab and wizard step 2):
// counts the ticked columns for "Add selected (n)", keeps the button disabled at
// zero, and filters the list as you type. Worked examples H4, E1.
export default class extends Controller {
  static targets = ["row", "submit", "counter"]

  connect() {
    this.count()
  }

  // Newly ticked columns only — already-added ones are checked and disabled
  count() {
    const ticked = this.element.querySelectorAll("input[name='keys[]']:checked:not(:disabled)").length
    if (this.hasCounterTarget) this.counterTarget.textContent = ticked
    if (this.hasSubmitTarget) this.submitTarget.disabled = ticked === 0
  }

  filter(e) {
    const query = e.target.value.toLowerCase().trim()
    if (query) this.element.querySelectorAll("details").forEach(d => { d.open = true })
    this.rowTargets.forEach(row => {
      row.classList.toggle("d-none", query !== "" && !(row.dataset.searchText || "").includes(query))
    })
  }
}
