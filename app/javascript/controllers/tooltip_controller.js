import { Controller } from "@hotwired/stimulus"
import * as bootstrap from "bootstrap"

export default class extends Controller {
  connect() {
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
    this.tooltipElements?.forEach((element) => {
      bootstrap.Tooltip.getInstance(element)?.dispose()
    })
  }
}
