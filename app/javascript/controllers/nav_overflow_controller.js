import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["nav", "item", "more", "moreDropdown", "reportsDropdown", "moreReportsHeader", "moreReportsDivider"]

  connect() {
    this.recalculate()
    this.resizeObserver = new ResizeObserver(() => this.recalculate())
    this.resizeObserver.observe(this.navTarget)
  }

  disconnect() {
    if (this.resizeObserver) {
      this.resizeObserver.disconnect()
    }
  }

  recalculate() {
    const navWidth = this.navTarget.offsetWidth
    const moreWidth = this.hasMoreTarget ? this.moreTarget.offsetWidth || 100 : 100
    const reportsWidth = this.hasReportsDropdownTarget ? this.reportsDropdownTarget.offsetWidth || 100 : 0

    let currentWidth = 0
    let overflowIndices = []
    const padding = 20 // Safety margin

    // First pass: identify which items overflow
    this.itemTargets.forEach((item, index) => {
      item.classList.remove('d-none')
      const itemWidth = item.offsetWidth

      // If we are getting close to the end, we need to account for the "More" button width
      // We assume if one item overflows, we'll need the "More" button
      if (currentWidth + itemWidth + reportsWidth + padding > navWidth) {
         // Check if it fits even if we add 'More'
         if (currentWidth + itemWidth + moreWidth + reportsWidth + padding > navWidth) {
            overflowIndices.push(index)
         } else {
            currentWidth += itemWidth
         }
      } else {
        currentWidth += itemWidth
      }
    })

    // Update visibility of items and their clones in dropdown
    const dropdownItems = this.moreDropdownTarget.querySelectorAll('[data-index]')

    if (overflowIndices.length > 0) {
      this.moreTarget.classList.remove('d-none')

      this.itemTargets.forEach((item, index) => {
        const dropdownItem = Array.from(dropdownItems).find(el => el.dataset.index == index)
        if (overflowIndices.includes(index)) {
          item.classList.add('d-none')
          if (dropdownItem) dropdownItem.classList.remove('d-none')
        } else {
          item.classList.remove('d-none')
          if (dropdownItem) dropdownItem.classList.add('d-none')
        }
      })

      // Move reports to "More" if overflow exists
      if (this.hasReportsDropdownTarget) {
        this.reportsDropdownTarget.classList.add('d-none')
        if (this.hasMoreReportsHeaderTarget) this.moreReportsHeaderTarget.classList.remove('d-none')
        if (this.hasMoreReportsDividerTarget) this.moreReportsDividerTarget.classList.remove('d-none')

        // Ensure all report items in "More" are visible
        this.moreDropdownTarget.querySelectorAll('.report-item').forEach(el => el.classList.remove('d-none'))
      }
    } else {
      this.moreTarget.classList.add('d-none')
      this.itemTargets.forEach(item => item.classList.remove('d-none'))

      // Show reports dropdown separately if no overflow
      if (this.hasReportsDropdownTarget) {
        this.reportsDropdownTarget.classList.remove('d-none')
        if (this.hasMoreReportsHeaderTarget) this.moreReportsHeaderTarget.classList.add('d-none')
        if (this.hasMoreReportsDividerTarget) this.moreReportsDividerTarget.classList.add('d-none')

        // Hide report items in "More"
        this.moreDropdownTarget.querySelectorAll('.report-item').forEach(el => el.classList.add('d-none'))
      }
    }
  }
}
