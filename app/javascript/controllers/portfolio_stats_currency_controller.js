import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "stats"]
  static values = {
    portfolioCompanyId: String,
    currentPath: String
  }

  connect() {
    console.log('[PortfolioStatsCurrency] Controller connected for portfolio company:', this.portfolioCompanyIdValue)
    console.log('[PortfolioStatsCurrency] Targets available:', {
      select: this.hasSelectTarget,
      stats: this.hasStatsTarget
    })
    console.log('[PortfolioStatsCurrency] Current path:', this.currentPathValue)
  }

  changeCurrency(event) {
    console.log('[PortfolioStatsCurrency] changeCurrency called')

    if (!this.hasSelectTarget) {
      console.error('[PortfolioStatsCurrency] Select target not found')
      return
    }

    if (!this.hasStatsTarget) {
      console.error('[PortfolioStatsCurrency] Stats target not found')
      return
    }

    const selectedCurrency = this.selectTarget.value
    const portfolioCompanyId = this.portfolioCompanyIdValue
    const statsContainer = this.statsTarget

    console.log('[PortfolioStatsCurrency] Selected currency:', selectedCurrency)

    // Build the URL with the new currency parameter
    let url
    try {
      url = new URL(this.currentPathValue, window.location.origin)
      console.log('[PortfolioStatsCurrency] Base URL constructed:', url.toString())
    } catch (error) {
      console.error('[PortfolioStatsCurrency] Error constructing URL:', error)
      console.error('[PortfolioStatsCurrency] currentPathValue:', this.currentPathValue)
      alert('Error constructing URL. Check console for details.')
      return
    }

    // Always set the display_currency parameter with the selected currency
    url.searchParams.set('display_currency', selectedCurrency)

    console.log('[PortfolioStatsCurrency] Final URL:', url.toString())

    // Show loading state
    statsContainer.style.opacity = '0.5'
    statsContainer.style.pointerEvents = 'none'

    // Fetch the updated stats via AJAX
    console.log('[PortfolioStatsCurrency] Fetching:', url.toString())
    fetch(url.toString(), {
      headers: {
        'Accept': 'text/html',
        'X-Requested-With': 'XMLHttpRequest'
      }
    })
    .then(response => {
      console.log('[PortfolioStatsCurrency] Response status:', response.status)
      if (!response.ok) {
        throw new Error(`Network response was not ok: ${response.status}`)
      }
      return response.text()
    })
    .then(html => {
      console.log('[PortfolioStatsCurrency] Response received, length:', html.length)

      // Create a temporary container to parse the response
      const tempDiv = document.createElement('div')
      tempDiv.innerHTML = html

      // Extract the stats cards from the response
      const newStatsCards = tempDiv.querySelector(`#stats_cards_${portfolioCompanyId}`)
      console.log('[PortfolioStatsCurrency] Looking for selector:', `#stats_cards_${portfolioCompanyId}`)
      console.log('[PortfolioStatsCurrency] Found stats cards:', !!newStatsCards)

      if (newStatsCards) {
        // Replace the stats container content
        statsContainer.innerHTML = newStatsCards.innerHTML
        statsContainer.style.opacity = '1'
        statsContainer.style.pointerEvents = 'auto'

        console.log('[PortfolioStatsCurrency] Stats updated successfully')

        // Update browser URL without reload
        if (window.history && window.history.pushState) {
          window.history.pushState({}, '', url.toString())
        }
      } else {
        throw new Error('Stats container not found in response')
      }
    })
    .catch(error => {
      console.error('[PortfolioStatsCurrency] Error fetching stats:', error)
      statsContainer.style.opacity = '1'
      statsContainer.style.pointerEvents = 'auto'
      alert('Failed to update currency. Please try again.')
    })
  }
}
