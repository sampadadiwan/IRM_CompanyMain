import { Controller } from "@hotwired/stimulus"
import Highcharts from "highcharts"
import "highcharts-more"

// Chart type definitions.
// isPie: true  → data formatted as pie points { name, y }  (no xAxis categories)
// isPie: false → data formatted as cartesian series with xAxis categories
const CHART_TYPES = {
  LineChart:      { type: "line",   isPie: false, label: "Line" },
  ColumnChart:    { type: "column", isPie: false, label: "Column" },
  BarChart:       { type: "bar",    isPie: false, label: "Bar (Horizontal)" },
  AreaChart:      { type: "area",   isPie: false, label: "Area" },
  SplineChart:    { type: "spline", isPie: false, label: "Spline" },
  PieChart:       { type: "pie",    isPie: true,  label: "Pie" },
  DonutChart:     { type: "pie",    isPie: true,  label: "Donut", innerSize: "50%" },
  HalfDonutChart: { type: "pie",    isPie: true,  label: "Half Donut", innerSize: "50%", semi: true },
}

const STORAGE_KEY       = "chart_switcher_type"
const URL_PARAM         = "chart_type"
const URL_DATE_PARAM    = "chart_date"
const DEFAULT_TYPE      = "DonutChart"

// Read the --pie-color-1 … --pie-color-10 CSS custom properties that are
// defined in kedaara.css.  Called once at connect() so the values are always
// resolved against the live :root style (supports dark-mode / theme switches).
function readPieColors() {
  const style = getComputedStyle(document.documentElement)
  const colors = []
  for (let i = 1; i <= 15; i++) {
    const val = style.getPropertyValue(`--pie-color-${i}`).trim()
    if (val) colors.push(val)
  }

  // Fall back to a sensible default palette if the CSS variables aren't loaded.
  // colors identical to PIE_CHART_COLORS in fund_statistics_helper.rb
  return colors.length ? colors : [
    "#5d87ff", "#65C18C", "#9ADCFF", "#364F6B", "#3FC1C9",
    "#54BAB9", "#FC5185", "#FFBCBC", "#EDF6E5", "#FF964F",
    "#006D74","#550C18","#00BFC6","#FF6B6B","#FFC857",
    "#6A5CFF","#000088","#F4A261","#7FB258","#DE61F4"
  ]
}

// Resolve a series colour:
//   1. If the series has a `tag`, look up --tag-color-<normalised-tag> in :root.
//      The normalisation matches the CSS variable names: lowercase, spaces → hyphens,
//      with "ic …" collapsed to "ic-case" and "audited…" to "audited".
//   2. Fall back to the next slot in the --pie-color-N palette.
function normaliseTagKey(tag) {
  if (!tag) return null
  const t = tag.trim().toLowerCase()
  if (t.startsWith("ic "))      return "ic-case"
  if (t.startsWith("audited"))  return "audited"
  return t.replace(/\s+/g, "-")
}

function resolveSeriesColors(rawData, palette, rootStyle) {
  let paletteIdx = 0
  const result = rawData.map(s => {
    // Always use the next color from the pie palette for each series.
    // The tag-based colors are intended for individual data points within a series,
    // not for the series themselves. Each series gets its own unique palette color.
    const color = palette[paletteIdx % palette.length]
    paletteIdx++
    return { ...s, color }
  })
  return result
}

export default class extends Controller {
  static targets = ["container", "typeSelect", "dateSelect", "dateSelectWrapper"]
  // Accept an optional initialTypeValue from server-side rendered data attribute.
  // Priority for resolved type will be: URL param > initialTypeValue > localStorage > default
  static values  = { chartData: Array, storageKey: String, initialType: String }

  connect() {
    // Resolve the --pie-color CSS palette once, at mount time.
    this._palette   = readPieColors()
    this._rootStyle = getComputedStyle(document.documentElement)

    // Per-page localStorage key: use the value passed from the view, falling back to a
    // path-based key so different pages don't share the same chart type preference.
    const storageKey   = this.hasStorageKeyValue && this.storageKeyValue
                         ? this.storageKeyValue
                         : `${STORAGE_KEY}:${window.location.pathname}`

  // Priority: URL param > server-provided initialType value > localStorage > default
  const searchParams   = new URLSearchParams(window.location.search)
  const urlType        = searchParams.get(URL_PARAM)
  const urlDateLabel   = searchParams.get(URL_DATE_PARAM)   // actual date label string, not an index
  // Treat an empty string from the data attribute as absent.
  const initialTypeValRaw = this.hasInitialTypeValue ? this.initialTypeValue : null
  const initialTypeVal = (initialTypeValRaw && initialTypeValRaw.trim() !== "") ? initialTypeValRaw : null
  const savedType      = localStorage.getItem(storageKey)
  const type = (urlType && CHART_TYPES[urlType])                     ? urlType
         : (initialTypeVal && CHART_TYPES[initialTypeVal])       ? initialTypeVal
         : (savedType && CHART_TYPES[savedType])                 ? savedType
         : DEFAULT_TYPE

    // Stash the resolved key so switch() can reuse it without re-computing
    this._storageKey = storageKey

    // Sync the dropdown to the resolved value
    if (this.hasTypeSelectTarget) {
      this.typeSelectTarget.value = type
    }

    // Populate date options, then restore the URL-specified label (if any)
    this.#populateDateSelect(urlDateLabel)

    // Only sync the full URL on initial load if there was a chart_type in the URL
    // or there is no server-provided initialType. If the server provided an
    // initialType, we should preserve it in the URL and avoid overwriting it
    // with a blank or default value.
    if (urlType || !initialTypeVal) {
      this.#syncUrl(type)
    }

    this.render(type)
  }

  switch(event) {
    const type = event.target.value
    if (!CHART_TYPES[type]) return

    // Persist in localStorage for same-browser navigation
    localStorage.setItem(this._storageKey, type)

    this.#syncUrl(type)
    this.render(type)
  }

  switchDate() {
    const type = this.hasTypeSelectTarget ? this.typeSelectTarget.value : DEFAULT_TYPE
    this.#syncUrl(type)
    this.render(type)
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  // Single source of truth for URL state: always writes chart_type;
  // writes chart_date (as the human-readable label string) for pie charts,
  // removes it for cartesian charts.
  // Also keeps any hidden form inputs with matching names in sync so that
  // the filter form submits the current chart state without a round-trip.
  #syncUrl(type) {
    const url = new URL(window.location.href)
    url.searchParams.set(URL_PARAM, type)

    let dateLabel = null
    if (CHART_TYPES[type]?.isPie && this.hasDateSelectTarget) {
      dateLabel = this.dateSelectTarget.value || null
    }

    if (dateLabel) {
      url.searchParams.set(URL_DATE_PARAM, dateLabel)
    } else {
      url.searchParams.delete(URL_DATE_PARAM)
    }

    history.replaceState(history.state, "", url.toString())

    // Keep hidden filter-form inputs in sync so submitting the search form
    // preserves the current chart type and date without a page round-trip.
    this.#syncHiddenField(URL_PARAM, type)
    this.#syncHiddenField(URL_DATE_PARAM, dateLabel)
  }

  // Find a hidden input by name anywhere in the document and update its value.
  // If value is null/empty, clear the field so it isn't submitted.
  #syncHiddenField(name, value) {
    const input = document.querySelector(`input[type="hidden"][name="${name}"]`)
    if (!input) return
    input.value = value || ""
  }

  // Build the date <select> from the unique labels in the chart data.
  // If urlDateLabel is provided (from the URL param), pre-select that label;
  // otherwise default to the last date that has at least one non-null value.
  #populateDateSelect(urlDateLabel = null) {
    if (!this.hasDateSelectTarget) return
    const rawData = this.chartDataValue
    if (!rawData.length) return

    // Collect all unique date labels across every series (preserving order)
    const seen = new Set()
    const labels = []
    rawData.forEach(s => (s.data || []).forEach(pt => {
      if (!seen.has(pt[0])) { seen.add(pt[0]); labels.push(pt[0]) }
    }))

    const sel = this.dateSelectTarget
    sel.innerHTML = ""
    labels.forEach((label) => {
      const opt = document.createElement("option")
      opt.value = label          // value IS the label — no index mapping needed
      opt.textContent = label
      sel.appendChild(opt)
    })

    // If a specific date label was in the URL, select it directly (value === label).
    // Fall back to the last date that has at least one non-null value.
    let defaultLabel = labels[labels.length - 1]
    if (urlDateLabel !== null && labels.includes(urlDateLabel)) {
      defaultLabel = urlDateLabel
    } else {
      for (let i = labels.length - 1; i >= 0; i--) {
        if (rawData.some(s => s.data[i] && s.data[i][1] != null)) { defaultLabel = labels[i]; break }
      }
    }
    sel.value = defaultLabel
  }

  #showDateSelect(visible) {
    if (this.hasDateSelectWrapperTarget) {
      this.dateSelectWrapperTarget.style.display = visible ? "" : "none"
    }
  }

  render(type) {
    const config = CHART_TYPES[type]
    if (!config) {
      console.warn(`chart-switcher: unknown chart type "${type}"`)
      return
    }

    // Show/hide the date picker depending on chart family
    this.#showDateSelect(config.isPie)

    // Rebuild mount point FIRST so the old chart's renderTo element is still
    // in the DOM when destroy() runs (Highcharts error #14 fires when it's gone).
    const wrapper = this.containerTarget
    const mount = document.createElement("div")
    mount.style.height = "300px"

    // Destroy existing chart while its container is still attached
    if (this.currentChart) {
      const old = this.currentChart
      this.currentChart = null
      try { old.destroy() } catch (_) { /* ignore */ }
    }

    // Now it's safe to swap the DOM
    wrapper.innerHTML = ""
    wrapper.appendChild(mount)

    const rawData = this.chartDataValue
    const coloredData = resolveSeriesColors(rawData, this._palette, this._rootStyle)

    let hcOptions

    if (config.isPie) {
      // The dateSelect value is now the label string (e.g. "31/03/2024").
      // Find the index of that label in each series' data array.
      const dateLabel = this.hasDateSelectTarget ? this.dateSelectTarget.value : ""

      // First, extract y-values for each series WITHOUT colors yet
      const pointsWithoutColors = rawData.map(s => {
        let y = null
        if (dateLabel) {
          const pt = (s.data || []).find(p => p[0] === dateLabel)
          y = pt ? pt[1] : null
        }
        // Fallback: last non-null value if the chosen date has no value for this series
        if (y == null) {
          const pts = (s.data || []).filter(p => p[1] != null)
          y = pts.length ? pts[pts.length - 1][1] : null
        }
        return { name: s.name, y: y != null ? Number(y) : 0 }
      }).filter(p => p.y !== 0)

      // Sort by value FIRST
      pointsWithoutColors.sort((a, b) => b.y - a.y)

      // Now assign colors based on the sorted order
      const piePoints = pointsWithoutColors.map((point, idx) => ({
        ...point,
        color: this._palette[idx % this._palette.length]
      }))

      const seriesConfig = {
        type: "pie",
        name: "Value",
        innerSize: config.innerSize || undefined,
        data: piePoints,
        ...(config.semi ? {
          startAngle: -90,
          endAngle:   90,
          center:     ["50%", "70%"],
          size:       "100%"
        } : {})
      }

      hcOptions = {
        chart: { type: "pie" },
        title: { text: null },
        subtitle: { text: null },
        tooltip: { pointFormat: "<b>{point.y}</b> ({point.percentage:.1f}%)" },
        plotOptions: {
          pie: {
            allowPointSelect: true,
            cursor: "pointer",
            dataLabels: {
              enabled: true,
              format: "<b>{point.name}</b>: {point.percentage:.1f}%",
              distance: config.semi ? -30 : 30
            }
          }
        },
        series: [seriesConfig]
      }

    } else {
      // Cartesian charts: line, column, bar, area, spline
      const series = coloredData.map(s => ({
        name:  s.name,
        type:  config.type,
        color: s.color,
        data:  (s.data || []).map(point => point[1] ?? null)
      }))
      const categories = rawData.length > 0
        ? (rawData[0].data || []).map(point => point[0])
        : []

      hcOptions = {
        chart: { type: config.type },
        title: { text: null },
        xAxis: { categories },
        yAxis: { title: { text: null } },
        plotOptions: {
          column: {
            pointWidth: 40,
            dataLabels: { enabled: false, format: "{point.y:,.2f}" }
          }
        },
        series
      }
    }

    this.currentChart = Highcharts.chart(mount, hcOptions)
  }

  disconnect() {
    if (this.currentChart) {
      try { this.currentChart.destroy() } catch (_) { /* ignore */ }
      this.currentChart = null
    }
  }
}

