import { Controller } from "@hotwired/stimulus"

// Client-side filter for the Support Agents index page.
// Shows/hides individual agent cards and their wrapping category sections
// based on a free-text query matched against each card's text content.
export default class extends Controller {
  static targets = ["query", "card", "section", "noResults", "clearButton"]

  filter() {
    const query = this.queryTarget.value.toLowerCase()
    let anyVisible = false

    this.cardTargets.forEach(card => {
      const text = card.textContent.toLowerCase()
      const visible = text.includes(query)
      card.classList.toggle("d-none", !visible)
      if (visible) anyVisible = true
    })

    // Hide entire sections that have no visible cards
    this.sectionTargets.forEach(section => {
      const visibleCards = section.querySelectorAll('[data-filter-agents-target="card"]:not(.d-none)')
      section.classList.toggle("d-none", visibleCards.length === 0)
    })

    // Toggle clear button visibility
    if (this.hasClearButtonTarget) {
      this.clearButtonTarget.style.display = query.length > 0 ? "" : "none"
    }

    // Show "no results" message when nothing matches
    if (this.hasNoResultsTarget) {
      this.noResultsTarget.classList.toggle("d-none", anyVisible || query.length === 0)
      if (query.length > 0 && !anyVisible) {
        this.noResultsTarget.textContent = `No agents match "${this.queryTarget.value}"`
      }
    }
  }

  clear() {
    this.queryTarget.value = ""
    this.filter()
    this.queryTarget.focus()
  }
}
