import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "row"]
  static values = {
    entityCurrency: String
  }

  connect() {
    console.debug('valuation_currency_filter: connected, entity currency=', this.entityCurrencyValue)
    // Apply initial filter after a small delay
    setTimeout(() => this.applyFilter(), 50)
  }

  applyFilter() {
    if (!this.hasSelectTarget) return

    const selectedCurrency = this.selectTarget.value || this.entityCurrencyValue
    console.debug('valuation_currency_filter: applyFilter', { selectedCurrency, entityCurrency: this.entityCurrencyValue })

    // Filter rows based on attribute currency
    this.rowTargets.forEach((tr) => {
      const rowCurrency = tr.getAttribute('data-row-currency')
      const isBaseRow = tr.getAttribute('data-is-base-row') === 'true'
      const attrCell = tr.querySelector('[data-valuation-currency-filter-attr]')
      const fullAttrLabel = tr.getAttribute('data-full-attr-label')

      // Logic:
      // - Base attributes (no suffix) represent the entity's base currency
      // - Attributes with _xxx suffix represent that specific currency
      let visible = false
      if (isBaseRow && selectedCurrency === this.entityCurrencyValue) {
        // Base attribute shown when entity currency is selected
        visible = true
      } else if (!isBaseRow && rowCurrency === selectedCurrency && selectedCurrency !== this.entityCurrencyValue) {
        // Currency-specific attribute shown when a non-entity currency is selected
        visible = true
      }

      // Always remove currency suffix from display for FMV/Equity metrics
      if (visible && attrCell && fullAttrLabel) {
        // Remove currency indicators from labels:
        // - (XXX) format: FMV(USD) -> FMV
        // - _xxx format: FMV_usd -> FMV
        // - (XXX mn/cr/etc): Equity Value (INR mn) -> Equity Value
        let cleanLabel = fullAttrLabel
          .replace(/\s*\([A-Z]{3}\s*(mn|cr|k|thousand|million|billion|lakh|crore)?\s*\)/gi, '')  // Remove (INR mn), (USD cr), etc.
          .replace(/\s*\([A-Z]{3}\)/gi, '')  // Remove (USD), (INR), etc.
          .replace(/\s*_[a-z]{3}$/i, '')      // Remove _usd, _inr, etc.
        attrCell.textContent = cleanLabel.trim()
      }

      tr.style.display = visible ? '' : 'none'
    })
  }
}
