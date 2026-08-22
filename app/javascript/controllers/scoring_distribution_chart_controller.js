import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

// Grade distribution bar chart — shared by the Portfolio Scoring Dashboard
// (7-band axis) and the Presentation Analyst Dashboard (6-band axis). Both
// pass their own labels/values/tiers, so the same chart works for either
// grade scale.
//
// Bar colours are passed in from the presenter rather than chosen here, so each
// band inherits its tier's colour and the chart stays reconciled with the stat
// cards. Clicking a bar navigates to that band's tier filter.
export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    labels: Array,   // grade letters, fixed axis (7 bands for scoring, 6 for presentation)
    values: Array,   // company count per band
    tiers: Array,    // tier slug per band; the colour is read from the theme
    urls: Array      // click-through URL per band, built server-side with the
                     // active sector/tag/basis filters already merged in
  }

  // Bootstrap role behind each tier. Colours are never hard-coded here: the
  // active Modernize colour theme (and light/dark mode) defines them, so the
  // chart follows whatever the user has selected. Covers both dashboards'
  // tier slugs — PortfolioScoringPresenter::TIERS and
  // PresentationAnalystPresenter::TIERS.
  static TIER_ROLE = {
    outperform: "success",
    on_track: "primary",
    watch: "warning",
    at_risk: "danger",
    not_scored: "secondary",
    high_accountability: "success",
    reliable: "primary",
    not_analyzed: "secondary"
  }

  connect() {
    this.renderChart()
  }

  // Resolves --bs-<role> against this element, so it picks up any theme scoping
  // on an ancestor rather than assuming :root.
  themeColor(role) {
    return getComputedStyle(this.element).getPropertyValue(`--bs-${role}`).trim()
  }

  barColors() {
    return this.tiersValue.map((tier) => {
      const role = this.constructor.TIER_ROLE[tier] || "secondary"
      // Empty means the variable is not defined on this page; let Chart.js fall
      // back to its own default rather than inventing a colour here.
      return this.themeColor(role) || undefined
    })
  }

  disconnect() {
    if (this.chart) this.chart.destroy()
  }

  renderChart() {
    const ctx = this.canvasTarget.getContext("2d")

    // Axis and grid chrome also come from the theme, so the chart stays legible
    // in dark mode and under every Modernize colour theme.
    const style = getComputedStyle(this.element)
    const bodyColor = style.getPropertyValue("--bs-body-color").trim() || "currentColor"
    const mutedColor = style.getPropertyValue("--bs-secondary-color").trim() || bodyColor
    const gridColor = style.getPropertyValue("--bs-border-color").trim()

    // Draws the count above each non-zero bar.
    const valueLabels = {
      id: "scoringValueLabels",
      afterDatasetsDraw: (chart) => {
        const { ctx: c } = chart
        chart.getDatasetMeta(0).data.forEach((bar, i) => {
          const value = chart.data.datasets[0].data[i]
          if (!value) return
          c.save()
          c.fillStyle = bodyColor
          c.font = "700 12px system-ui, -apple-system, sans-serif"
          c.textAlign = "center"
          c.fillText(value, bar.x, bar.y - 7)
          c.restore()
        })
      }
    }

    this.chart = new Chart(ctx, {
      type: "bar",
      plugins: [valueLabels],
      data: {
        labels: this.labelsValue,
        datasets: [{
          label: "Companies",
          data: this.valuesValue,
          backgroundColor: this.barColors(),
          borderRadius: { topLeft: 8, topRight: 8, bottomLeft: 2, bottomRight: 2 },
          borderSkipped: false,
          maxBarThickness: 64
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        layout: { padding: { top: 18 } },
        // Clicking a bar filters the table to the tier that band belongs to.
        onClick: (_event, elements) => this.navigateToTier(elements),
        onHover: (event, elements) => {
          event.native.target.style.cursor = elements.length ? "pointer" : "default"
        },
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: (item) => {
                const count = item.parsed.y
                return `${count} ${count === 1 ? "company" : "companies"}`
              }
            }
          }
        },
        scales: {
          x: {
            grid: { display: false },
            border: { color: gridColor },
            ticks: { color: bodyColor, font: { size: 12, weight: "600" } },
            title: { display: true, text: "Grade band (derived from overall score)",
                     color: mutedColor, font: { size: 11 } }
          },
          y: {
            beginAtZero: true,
            // Whole companies only — a fractional tick would be meaningless here.
            ticks: { stepSize: 1, precision: 0, color: mutedColor, font: { size: 11 } },
            grid: { color: gridColor },
            border: { display: false },
            title: { display: true, text: "Companies", color: mutedColor, font: { size: 11 } }
          }
        }
      }
    })
  }

  // Bars with a zero count are not clickable — there would be nothing to show.
  navigateToTier(elements) {
    if (!elements.length) return

    const index = elements[0].index
    if (!this.valuesValue[index]) return

    const url = this.urlsValue[index]
    if (url) window.location.href = url
  }
}
