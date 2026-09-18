/**
 * Stimulus controller for toggling KPI values between fund currency and
 * the portfolio company's reporting currency (kpi_currency).
 *
 * Swaps displayed text on elements marked with data-kpi-currency-toggle-target="cell"
 * between their data-fund-display and data-original-display attributes.
 *
 * @example
 *   <div data-controller="kpi-currency-toggle"
 *        data-kpi-currency-toggle-kpi-currency-value="USD"
 *        data-kpi-currency-toggle-fund-currency-value="INR">
 *     <button data-kpi-currency-toggle-target="button" data-action="click->kpi-currency-toggle#toggle">
 *       Viewing: INR (Fund)
 *     </button>
 *     <span data-kpi-currency-toggle-target="cell"
 *           data-fund-display="₹47,32,50,000"
 *           data-original-display="USD 5,000,000">₹47,32,50,000</span>
 *   </div>
 */
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cell", "button"]
  static values = {
    kpiCurrency: String,
    fundCurrency: String
  }

  connect() {
    this.showingOriginal = false
    try {
      const saved = localStorage.getItem("kpi_currency_toggle")
      if (saved === "original") {
        this.showingOriginal = true
        this._apply()
      }
    } catch (_e) {
      // localStorage unavailable — default to fund currency
    }
  }

  /** @param {Event} _event */
  toggle(_event) {
    this.showingOriginal = !this.showingOriginal
    this._apply()
    try {
      localStorage.setItem("kpi_currency_toggle", this.showingOriginal ? "original" : "fund")
    } catch (_e) {
      // localStorage unavailable — toggle still works for the session
    }
  }

  /** Swaps cell text and updates button label. */
  _apply() {
    this.cellTargets.forEach((cell) => {
      const fundDisplay = cell.dataset.fundDisplay
      const originalDisplay = cell.dataset.originalDisplay
      if (!fundDisplay || !originalDisplay) return

      cell.innerHTML = this.showingOriginal ? originalDisplay : fundDisplay
    })

    this.buttonTargets.forEach((btn) => {
      if (this.showingOriginal) {
        btn.innerHTML = `<i class="ti ti-arrows-exchange me-1"></i>Viewing: ${this.kpiCurrencyValue} (KPI)`
        btn.classList.remove("btn-outline-secondary")
        btn.classList.add("btn-info")
      } else {
        btn.innerHTML = `<i class="ti ti-arrows-exchange me-1"></i>Viewing: ${this.fundCurrencyValue} (Fund)`
        btn.classList.remove("btn-info")
        btn.classList.add("btn-outline-secondary")
      }
    })
  }
}
