// app/javascript/controllers/chart_renderer_controller.js
import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"   // core ESM
Chart.register(...registerables)                  // <-- force-register all types/scales/elements

export default class extends Controller {
  static targets = ["canvas"]
  static values = { spec: Object }

  connect() {
    try {
      const ctx = this.canvasTarget.getContext("2d")
      this.chart = new Chart(ctx, this.specValue) // now "bar" is registered
    } catch (e) {
      console.error("Chart render failed", e)
    }
  }

  disconnect() { this.chart?.destroy() }
}
