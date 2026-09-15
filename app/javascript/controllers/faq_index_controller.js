import { Controller } from "@hotwired/stimulus"

// Filters the all-FAQs page (/faqs): hides questions whose question or answer does not
// contain every search word, and hides guides left with no visible questions. Matches are not
// auto-expanded: caphive.js keeps a single accordion item open at a time.
export default class extends Controller {
  static targets = ["input", "item", "section", "noResults", "clearButton"]

  filter() {
    const words = this.inputTarget.value.toLowerCase().split(/\s+/).filter(Boolean)
    let visible = 0

    this.itemTargets.forEach((item) => {
      const text = item.textContent.toLowerCase()
      const match = words.every((word) => text.includes(word))
      item.hidden = !match
      if (match) visible++
    })

    this.sectionTargets.forEach((section) => {
      section.hidden = !section.querySelector("details:not([hidden])")
    })

    this.noResultsTarget.classList.toggle("is-hidden", visible > 0)
    this.clearButtonTarget.classList.toggle("is-hidden", words.length === 0)
  }

  clear() {
    this.inputTarget.value = ""
    this.filter()
    this.inputTarget.focus()
  }
}
