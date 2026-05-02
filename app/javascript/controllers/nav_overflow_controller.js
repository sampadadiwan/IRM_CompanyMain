import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["nav", "item", "more", "moreDropdown", "reportsDropdown", "moreReportsHeader", "moreReportsDivider", "dashboardSelector"]

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
    const containerWidth = this.navTarget.parentElement.offsetWidth;
    const reportsWidth = this.hasReportsDropdownTarget ? this.reportsDropdownTarget.offsetWidth || 50 : 0;
    const dashboardSelectorWidth = this.hasDashboardSelectorTarget ? this.dashboardSelectorTarget.offsetWidth || 180 : 0;
    const gapWidth = 8; // gap-2 is 0.5rem = 8px
    const padding = 20; // Increased safety margin

    // Measure the "More" button by temporarily making it visible
    let moreWidth = 180;
    if (this.hasMoreTarget) {
      const wasHidden = this.moreTarget.classList.contains('d-none');
      this.moreTarget.classList.remove('d-none');
      moreWidth = this.moreTarget.offsetWidth || 180;
      if (wasHidden) this.moreTarget.classList.add('d-none');
    }

    // Available width once we reserve space for "More", Reports, and Dashboard Selector
    const reservedWidth = moreWidth + reportsWidth + dashboardSelectorWidth + padding;
    const availableWidth = containerWidth - reservedWidth;

    let currentWidth = 0;
    let overflowIndices = [];

    // First pass: identify which items overflow
    this.itemTargets.forEach((item, index) => {
      item.classList.remove('d-none')
      const itemWidth = item.offsetWidth

      // Add gap width for all items except the first one
      const effectiveItemWidth = index === 0 ? itemWidth : itemWidth + gapWidth;

      if (currentWidth + effectiveItemWidth > availableWidth) {
        overflowIndices.push(index)
      } else {
        currentWidth += effectiveItemWidth
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
