import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "stats"]
  static values = {
    // Single portfolio mode
    portfolioCompanyId: String,
    currentPath: String,
    // Multi portfolio mode (present when investor_ids are passed)
    investorIds: Array,
    fields: String,
    decimals: Number,
    forceUnits: String,
    trackingCurrency: String,
    currency: String,
    widgetSize: String,
    widgetId: String
  }

  get isMultiMode() {
    return this.hasInvestorIdsValue && this.investorIdsValue.length > 0
  }

  connect() {
    if (this.isMultiMode) {
      console.log('[PortfolioStatsCurrency] Multi-portfolio mode, investor ids:', this.investorIdsValue)
    } else {
      console.log('[PortfolioStatsCurrency] Single portfolio mode, company id:', this.portfolioCompanyIdValue)
    }
  }

  changeCurrency(event) {
    if (!this.hasSelectTarget) {
      console.error('[PortfolioStatsCurrency] Select target not found')
      return
    }
    if (!this.hasStatsTarget) {
      console.error('[PortfolioStatsCurrency] Stats target not found')
      return
    }

    const selectedCurrency = this.selectTarget.value
    const statsContainer = this.statsTarget

    let url
    try {
      if (this.isMultiMode) {
        // Multi: call investor action directly
        url = new URL('/investors/multi_portfolio_stat_currency', window.location.origin)

        // Pass investor ids
        this.investorIdsValue.forEach(id => url.searchParams.append('investor_ids[]', id))

        // Forward existing filter params from current URL (fund_ids, tag_list, sector)
        const currentUrl = new URL(window.location.href)
        ;['fund_ids', 'tag_list', 'sector'].forEach(key => {
          currentUrl.searchParams.getAll(key + '[]').forEach(val => url.searchParams.append(key + '[]', val))
          currentUrl.searchParams.getAll(key).forEach(val => url.searchParams.append(key, val))
        })

        // Forward widget config
        if (this.hasFieldsValue && this.fieldsValue)                     url.searchParams.set('fields', this.fieldsValue)
        if (this.hasDecimalsValue && this.decimalsValue)                  url.searchParams.set('decimals', this.decimalsValue)
        if (this.hasForceUnitsValue && this.forceUnitsValue)              url.searchParams.set('force_units', this.forceUnitsValue)
        if (this.hasTrackingCurrencyValue && this.trackingCurrencyValue)  url.searchParams.set('tracking_currency', this.trackingCurrencyValue)
        if (this.hasCurrencyValue && this.currencyValue)                  url.searchParams.set('currency', this.currencyValue)
        if (this.hasWidgetSizeValue && this.widgetSizeValue)              url.searchParams.set('widget_size', this.widgetSizeValue)
        if (this.hasWidgetIdValue && this.widgetIdValue)                  url.searchParams.set('widget_id', this.widgetIdValue)
      } else {
        // Single: re-fetch the current page
        url = new URL(this.currentPathValue, window.location.origin)
      }
    } catch (error) {
      console.error('[PortfolioStatsCurrency] Error constructing URL:', error)
      return
    }

    url.searchParams.set('display_currency', selectedCurrency)
    console.log('[PortfolioStatsCurrency] Fetching:', url.toString())

    statsContainer.style.opacity = '0.5'
    statsContainer.style.pointerEvents = 'none'

    fetch(url.toString(), {
      headers: {
        'Accept': 'text/html',
        'X-Requested-With': 'XMLHttpRequest'
      }
    })
    .then(response => {
      if (!response.ok) {
        return response.text().then(body => {
          throw new Error(`HTTP ${response.status}: ${body.substring(0, 500)}`)
        })
      }
      return response.text()
    })
    .then(html => {
      const tempDiv = document.createElement('div')
      tempDiv.innerHTML = html

      const selector = this.isMultiMode
        ? `#multi_portfolio_stats_cards_${this.widgetIdValue}`
        : `#stats_cards_${this.portfolioCompanyIdValue}`

      console.log('[PortfolioStatsCurrency] widgetIdValue:', this.widgetIdValue, '| selector:', selector)

      const newStats = tempDiv.querySelector(selector)
      console.log('[PortfolioStatsCurrency] Looking for:', selector, '— found:', !!newStats)
      if (!newStats) {
        console.error('[PortfolioStatsCurrency] Response HTML:', html.substring(0, 1000))
      }

      if (newStats) {
        statsContainer.innerHTML = newStats.innerHTML
        statsContainer.style.opacity = '1'
        statsContainer.style.pointerEvents = 'auto'

        // Only push URL state in single mode (multi uses a dedicated endpoint)
        if (!this.isMultiMode && window.history?.pushState) {
          window.history.pushState({}, '', url.toString())
        }
      } else {
        throw new Error(`Stats container "${selector}" not found in response`)
      }
    })
    .catch(error => {
      console.error('[PortfolioStatsCurrency] Error:', error)
      statsContainer.style.opacity = '1'
      statsContainer.style.pointerEvents = 'auto'
      alert('Failed to update currency. Please try again.')
    })
  }
}

