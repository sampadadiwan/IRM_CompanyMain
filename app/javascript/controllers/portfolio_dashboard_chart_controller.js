import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    labels: Array,
    values: Array
  }

  connect() {
    this.tabEl = document.querySelector('a[href="#portfolio-reports-tab"]')
    if (this.tabEl) {
      this.tabHandler = () => this.resizeChart()
      this.tabEl.addEventListener("shown.bs.tab", this.tabHandler)
    }
    this.renderChart()
  }

  disconnect() {
    if (this.chart) this.chart.destroy()
    if (this.tabEl && this.tabHandler) {
      this.tabEl.removeEventListener("shown.bs.tab", this.tabHandler)
    }
  }

  resizeChart() {
    if (this.chart) this.chart.resize()
  }

  renderChart() {
    const ctx = this.canvasTarget.getContext("2d")
    this.chart = new Chart(ctx, {
      type: "bar",
      data: {
        labels: this.labelsValue,
        datasets: [{
          label: "Companies Missing",
          data: this.valuesValue,
          backgroundColor: [
            "#e74c3c", "#e67e22", "#3498db", "#9b59b6", "#1abc9c", "#f39c12"
          ].slice(0, this.valuesValue.length),
          borderRadius: 6,
          barThickness: 40
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: (ctx) => `${ctx.parsed.y} companies`
            }
          }
        },
        scales: {
          y: {
            beginAtZero: true,
            ticks: { stepSize: 1, precision: 0 },
            title: { display: true, text: "Companies Missing" }
          }
        }
      }
    })
  }
}
