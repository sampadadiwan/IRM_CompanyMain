import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

// Portfolio average score per month, for the Trajectory panel.
//
// Deliberately a sparkline rather than a full chart: it answers "which way are
// we heading", not "what exactly was the average in March". The y-axis is
// clamped around the data instead of anchored at zero, because every score sits
// in 0-100 and a zero-based axis would flatten every real movement into a line.
export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    labels: Array, // month labels, oldest first
    values: Array, // portfolio average score that month
    counts: Array  // companies scored that month, shown in the tooltip
  }

  connect() {
    this.renderChart()
  }

  disconnect() {
    if (this.chart) this.chart.destroy()
  }

  renderChart() {
    const ctx = this.canvasTarget.getContext("2d")

    // Pad the visible range so the line has room to breathe, without letting it
    // escape the valid 0-100 score range.
    const values = this.valuesValue
    const min = Math.max(0, Math.min(...values) - 8)
    const max = Math.min(100, Math.max(...values) + 8)

    // Line colour comes from the active theme's primary, so the sparkline
    // follows the user's chosen colour theme instead of a fixed blue.
    const style = getComputedStyle(this.element)
    const accent = style.getPropertyValue("--bs-primary").trim()
    const surface = style.getPropertyValue("--bs-body-bg").trim()

    // Soft fill under the line: the accent fading into the page surface.
    // Only built when both variables resolved — addColorStop throws a
    // SyntaxError on anything it cannot parse (a keyword like "currentColor"
    // included), which would abort the render and leave a blank canvas.
    let fill
    if (accent && surface) {
      fill = ctx.createLinearGradient(0, 0, 0, 150)
      fill.addColorStop(0, accent)
      fill.addColorStop(1, surface)
    }

    this.chart = new Chart(ctx, {
      type: "line",
      data: {
        labels: this.labelsValue,
        datasets: [{
          data: values,
          borderColor: accent || undefined,
          backgroundColor: fill,
          fill: Boolean(fill),
          borderWidth: 2,
          tension: 0.35,
          pointRadius: 3,
          pointBackgroundColor: surface || undefined,
          pointBorderColor: accent || undefined,
          pointBorderWidth: 2,
          pointHoverRadius: 5
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: (item) => {
                const count = this.countsValue[item.dataIndex]
                return `Average ${item.parsed.y} · ${count} ${count === 1 ? "company" : "companies"} scored`
              }
            }
          }
        },
        scales: {
          x: {
            grid: { display: false },
            ticks: { font: { size: 10 }, maxRotation: 0, autoSkipPadding: 12 }
          },
          y: {
            min: min,
            max: max,
            ticks: { stepSize: 10, font: { size: 10 } },
            grid: { color: style.getPropertyValue("--bs-border-color").trim() || undefined }
          }
        }
      }
    })
  }
}
