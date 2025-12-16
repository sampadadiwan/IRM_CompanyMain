import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Prefer the single global Bootstrap instance (from the Modernize layout bundle).
    // This avoids loading Bootstrap twice (UMD + ESM), which can break dropdown behavior.
    const bootstrap = window.bootstrap
    if (!bootstrap?.Tooltip) return

    // Bootstrap 5 uses `data-bs-toggle="tooltip"`.
    // Keep backward-compat for any legacy markup using `data-toggle="tooltip"`.
    this.tooltipElements = Array.from(
      this.element.querySelectorAll("[data-bs-toggle='tooltip'], [data-toggle='tooltip']")
    )

    this.tooltipElements.forEach((element) => {
      bootstrap.Tooltip.getOrCreateInstance(element)
    })
  }

  disconnect() {
    const bootstrap = window.bootstrap
    if (!bootstrap?.Tooltip) return

    this.tooltipElements?.forEach((element) => {
      bootstrap.Tooltip.getInstance(element)?.dispose()
    })
  }
}
