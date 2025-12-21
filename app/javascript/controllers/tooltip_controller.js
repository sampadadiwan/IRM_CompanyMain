import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.bootstrap = window.bootstrap
    if (!this.bootstrap?.Tooltip) return

    this.initTooltips(this.element)

    // If this controller is on/near a dropdown, initialize tooltips when it opens.
    this.onDropdownShown = (event) => {
      // event.target is the dropdown toggle; menu is next to it in the DOM
      const dropdownRoot = event.target?.closest(".dropdown") || this.element
      this.initTooltips(dropdownRoot)
    }

    document.addEventListener("shown.bs.dropdown", this.onDropdownShown)

    // Listen for custom event to re-initialize tooltips if content changes dynamically
    this.onReinit = () => this.initTooltips(this.element)
    this.element.addEventListener("tooltip:reinit", this.onReinit)

    // Also listen for turbo:render to handle global page/frame changes
    this.onTurboRender = () => this.initTooltips(this.element)
    document.addEventListener("turbo:render", this.onTurboRender)
  }

  disconnect() {
    if (!this.bootstrap?.Tooltip) return
    document.removeEventListener("shown.bs.dropdown", this.onDropdownShown)
    document.removeEventListener("turbo:render", this.onTurboRender)
    this.element.removeEventListener("tooltip:reinit", this.onReinit)

    // Dispose any tooltips we created
    this.tooltipElements?.forEach((el) => {
      this.bootstrap.Tooltip.getInstance(el)?.dispose()
    })
  }

  initialize() {
    // Ensure we have an array to track elements
    this.tooltipElements = []
  }

  initTooltips(root) {
    const elements = Array.from(
      root.querySelectorAll("[data-bs-toggle='tooltip'], [data-toggle='tooltip']")
    )

    // Track only the ones we touched so we can dispose later.
    this.tooltipElements = this.tooltipElements || []

    elements.forEach((el) => {
      this.bootstrap.Tooltip.getOrCreateInstance(el)
      if (!this.tooltipElements.includes(el)) this.tooltipElements.push(el)
    })
  }
}
