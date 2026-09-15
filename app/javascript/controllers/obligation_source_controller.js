import { Controller } from "@hotwired/stimulus"

/**
 * Toggles the obligation source picker between Side Letter (for SLO)
 * and Portfolio Investment (for CP/CS) based on the legal_category select.
 *
 * @example
 *   <div data-controller="obligation-source">
 *     <select data-obligation-source-target="category" data-action="change->obligation-source#toggle">
 *     <div data-obligation-source-target="sideLetter">...</div>
 *     <div data-obligation-source-target="portfolioInvestment">...</div>
 *   </div>
 */
export default class extends Controller {
  static targets = ["category", "sideLetter", "portfolioInvestment"]

  connect() {
    this.toggle()
  }

  toggle() {
    const value = this.categoryTarget.value
    const isCpCs = (value === "condition_precedent" || value === "condition_subsequent")

    if (this.hasSideLetterTarget) {
      this.sideLetterTarget.hidden = isCpCs
      const select = this.sideLetterTarget.querySelector("select")
      if (select) select.disabled = isCpCs
    }

    if (this.hasPortfolioInvestmentTarget) {
      this.portfolioInvestmentTarget.hidden = !isCpCs
      const select = this.portfolioInvestmentTarget.querySelector("select")
      if (select) select.disabled = !isCpCs
    }
  }
}
