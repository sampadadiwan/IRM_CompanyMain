import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    console.log("TooltipController#connect", this.element)
    this.bootstrap = window.bootstrap
    if (!this.bootstrap?.Tooltip) {
      console.warn("Bootstrap Tooltip not found on window.bootstrap")
      return
    }

    this.initTooltips(this.element)

    // If this controller is on/near a dropdown, initialize tooltips when it opens.
    this.onDropdownShown = (event) => {
      console.log("TooltipController: shown.bs.dropdown", event.target)
      // event.target is the dropdown toggle; menu is next to it in the DOM
      const dropdownRoot = event.target?.closest(".dropdown") || this.element
      this.initTooltips(dropdownRoot)
    }

    document.addEventListener("shown.bs.dropdown", this.onDropdownShown)

    // Listen for custom event to re-initialize tooltips if content changes dynamically
    this.onReinit = () => {
      console.log("TooltipController: tooltip:reinit")
      this.initTooltips(this.element)
    }
    this.element.addEventListener("tooltip:reinit", this.onReinit)

    // Handle Turbo Frame loads. When a frame inside this controller's scope loads,
    // it triggers 'turbo:frame-load'. If the controller is ON the frame, connect() handles it.
    this.onFrameLoad = (event) => {
      console.log("TooltipController: turbo:frame-load", event.target)
      // If the frame is a descendant of this controller, re-init.
      if (this.element.contains(event.target)) {
        console.log("TooltipController: Initializing tooltips for frame", event.target)
        this.initTooltips(event.target)
      } else {
        console.log("TooltipController: Frame loaded but not descendant of this.element", event.target)
      }
    }
    document.addEventListener("turbo:frame-load", this.onFrameLoad)

    // Also listen for turbo:render to handle global page/frame changes
    this.onTurboRender = () => {
      console.log("TooltipController: turbo:render")
      this.initTooltips(this.element)
    }
    document.addEventListener("turbo:render", this.onTurboRender)
  }

  disconnect() {
    console.log("TooltipController#disconnect", this.element)
    if (!this.bootstrap?.Tooltip) return
    document.removeEventListener("shown.bs.dropdown", this.onDropdownShown)
    document.removeEventListener("turbo:render", this.onTurboRender)
    document.removeEventListener("turbo:frame-load", this.onFrameLoad)
    this.element.removeEventListener("tooltip:reinit", this.onReinit)

    // Dispose any tooltips we created
    this.tooltipElements?.forEach((el) => {
      this.bootstrap.Tooltip.getInstance(el)?.dispose()
    })
  }

  initialize() {
    console.log("TooltipController#initialize")
    // Ensure we have an array to track elements
    this.tooltipElements = []
  }

  initTooltips(root) {
    const elements = Array.from(
      root.querySelectorAll("[data-bs-toggle='tooltip'], [data-toggle='tooltip']")
    )
    console.log(`TooltipController#initTooltips found ${elements.length} elements in`, root)

    // Track only the ones we touched so we can dispose later.
    this.tooltipElements = this.tooltipElements || []

    elements.forEach((el) => {
      this.bootstrap.Tooltip.getOrCreateInstance(el)
      if (!this.tooltipElements.includes(el)) this.tooltipElements.push(el)
    })
  }
}
