import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "row"]
  static values = {
    entityCurrency: String
  }

  connect() {
    console.debug('fund_ratios_filter: connected, entity currency=', this.entityCurrencyValue)
    // Apply initial filter after a small delay to allow DataTables to initialize
    setTimeout(() => this.applyFilter(), 50)
  }

  applyFilter() {
    if (!this.hasSelectTarget) return

    const selectedCurrency = this.selectTarget.value || this.entityCurrencyValue
    console.debug('fund_ratios_filter: applyFilter', { selectedCurrency, entityCurrency: this.entityCurrencyValue })

    const table = this.element.querySelector('table.datatable')

    // If DataTables is active, use its API so filtering persists across redraws
    if (window.jQuery?.fn?.dataTable?.isDataTable(table)) {
      try {
        const dt = window.jQuery(table).DataTable()
        dt.rows().every(function() {
          const node = this.node()
          if (!node) return

          const metricCurrency = node.getAttribute('data-metric-currency')
          const isBase = node.getAttribute('data-is-base') === 'true'
          const fullMetricName = node.getAttribute('data-metric')
          const metricCell = node.querySelector('td:nth-child(1)')

          // Logic:
          // - Base metrics (no suffix) represent the entity's base currency
          // - Metrics with (XXX) suffix represent that specific currency
          // Show the metric if:
          //   - It's a base metric and selected currency is entity currency
          //   - It has a currency suffix that matches the selected currency
          let visible = false
          if (isBase && selectedCurrency === this.entityCurrencyValue) {
            // Base metric shown when entity currency is selected
            visible = true
          } else if (!isBase && metricCurrency === selectedCurrency) {
            // Currency-specific metric shown when that currency is selected
            visible = true
          }

          // Always remove currency suffix from display for cleaner presentation
          if (visible && metricCell && fullMetricName) {
            const cleanName = fullMetricName.replace(/\s*\([A-Z]{3}\)$/, '')
            metricCell.textContent = cleanName.trim()
          }

          this.visible(visible)
        }.bind(this))
        dt.draw(false)
        return
      } catch (err) {
        console.warn('fund_ratios_filter: DataTables filtering failed, falling back to DOM. error:', err)
      }
    }

    // Fallback: manipulate row display directly
    this.rowTargets.forEach((tr) => {
      const metricCurrency = tr.getAttribute('data-metric-currency')
      const isBase = tr.getAttribute('data-is-base') === 'true'
      const fullMetricName = tr.getAttribute('data-metric')
      const metricCell = tr.querySelector('td:nth-child(1)')

      // Logic:
      // - Base metrics (no suffix) represent the entity's base currency
      // - Metrics with (XXX) suffix represent that specific currency
      let visible = false
      if (isBase && selectedCurrency === this.entityCurrencyValue) {
        // Base metric shown when entity currency is selected
        visible = true
      } else if (!isBase && metricCurrency === selectedCurrency) {
        // Currency-specific metric shown when that currency is selected
        visible = true
      }

      // Always remove currency suffix from display for cleaner presentation
      if (visible && metricCell && fullMetricName) {
        const cleanName = fullMetricName.replace(/\s*\([A-Z]{3}\)$/, '')
        metricCell.textContent = cleanName.trim()
      }

      tr.style.display = visible ? '' : 'none'
    })
  }
}
