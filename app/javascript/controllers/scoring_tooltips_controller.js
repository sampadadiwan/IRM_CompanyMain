import { Controller } from "@hotwired/stimulus"

// Activates Bootstrap tooltips inside the Portfolio Scoring Dashboard.
//
// Bootstrap 5 tooltips are opt-in: a `data-bs-toggle="tooltip"` attribute does
// nothing until something calls `new bootstrap.Tooltip(el)`. This app has no
// global initializer, so tooltip markup elsewhere is inert — this controller
// wires up only the elements inside its own scope.
//
// It re-scans after Turbo Frame swaps because the company table renders inside
// a frame: rows replaced by a search or a page change would otherwise come back
// without tooltips.
export default class extends Controller {
  connect() {
    this.tooltips = []
    this.render()

    // The table frame reloads on search and pagination; re-bind what it brings.
    this.frameHandler = () => this.render()
    this.element.addEventListener("turbo:frame-load", this.frameHandler)
  }

  disconnect() {
    this.element.removeEventListener("turbo:frame-load", this.frameHandler)
    this.destroyAll()
  }

  render() {
    // bootstrap is loaded globally by the layout (CDN bundle), not imported.
    const bootstrap = window.bootstrap
    if (!bootstrap || !bootstrap.Tooltip) return

    this.destroyAll()

    this.element.querySelectorAll('[data-bs-toggle="tooltip"]').forEach((el) => {
      // Skip anything already carrying an instance, so a double render cannot
      // stack two tooltips on one element.
      if (bootstrap.Tooltip.getInstance(el)) return

      this.tooltips.push(
        new bootstrap.Tooltip(el, { container: "body", delay: { show: 120, hide: 40 } })
      )
    })
  }

  // Tooltips append their own nodes to <body>, so they outlive the element they
  // came from unless disposed explicitly.
  destroyAll() {
    this.tooltips.forEach((tooltip) => tooltip.dispose())
    this.tooltips = []
  }
}
