import { Controller } from "@hotwired/stimulus"

// Lets the stat cards atop the Remittance Reconciliation panel act as toggleable
// filters over the deposit table below, entirely client-side — there is no separate
// index to navigate to for a single call's deposits. Clicking a card shows only rows
// whose tier matches (or, for the "discrepancy" card, whose source-of-funds tag is
// "Not from KYC account"); clicking the active card again clears the filter.
export default class extends Controller {
  static targets = ["card", "row", "emptyRow", "body"]
  static values = { active: { type: String, default: "" } }

  toggle(event) {
    const filter = event.currentTarget.dataset.filter
    this.activeValue = this.activeValue === filter ? "" : filter
  }

  activeValueChanged() {
    const active = this.activeValue

    this.cardTargets.forEach((card) => {
      card.classList.toggle("reconciliation-stat-card--active", active !== "" && card.dataset.filter === active)
    })

    let visibleCount = 0
    this.rowTargets.forEach((row) => {
      const matches = active === "" || row.dataset.filter === active ||
        (active === "discrepancy" && row.dataset.discrepancy === "true")
      row.classList.toggle("d-none", !matches)
      if (matches) visibleCount += 1
    })

    if (this.hasEmptyRowTarget) {
      this.emptyRowTarget.classList.toggle("d-none", visibleCount > 0)
    }
  }
}
