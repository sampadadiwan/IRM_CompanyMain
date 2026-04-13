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
    const navWidth = this.navTarget.offsetWidth;
    const reportsWidth = this.hasReportsDropdownTarget ? this.reportsDropdownTarget.offsetWidth || 50 : 0;
    const padding = 5; // Safety margin

    // Measure the "More" button by temporarily making it visible
    let moreWidth = 50;
    if (this.hasMoreTarget) {
      const wasHidden = this.moreTarget.classList.contains('d-none');
      this.moreTarget.classList.remove('d-none');
      moreWidth = this.moreTarget.offsetWidth || 50;
      console.log(`Measured "More" width: ${moreWidth}px (was hidden: ${wasHidden})`);
      if (wasHidden) this.moreTarget.classList.add('d-none');
    }

    // Available width once we reserve space for "More" and Reports
    const availableWidth = navWidth - moreWidth - reportsWidth - padding;

    let currentWidth = 0;
    let overflowIndices = [];

    // First pass: identify which items overflow
    this.itemTargets.forEach((item, index) => {
      item.classList.remove('d-none')
      const itemWidth = item.offsetWidth

      if (currentWidth + itemWidth > availableWidth) {
        overflowIndices.push(index)
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
