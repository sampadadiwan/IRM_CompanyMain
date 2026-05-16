import { Controller } from "@hotwired/stimulus"

// Renders the LP × Portfolio Company heatmap as an HTML table.
// Pure CSS/HTML approach — no Highcharts colorAxis (which cannot reliably
// colour cells when raw dollar values are orders of magnitude apart).
export default class extends Controller {
  static targets = ["heatmap"]
  static values  = {
    heatmapData:  Array,   // [{ x, y, value }]
    lpNames:      Array,   // y-axis rows (LP names)
    companyNames: Array,   // x-axis columns (fund or company names)
    currency:     String,
    title:        String
  }

  connect() {
    // Wait for collapse animation before measuring the container
    setTimeout(() => this.renderHeatmap(), 400)
  }

  disconnect() {
    if (this._heatmapChart) { this._heatmapChart.destroy(); this._heatmapChart = null }
  }

  renderHeatmap() {
    const currency  = this.currencyValue || ""
    const companies = this.companyNamesValue
    const lps       = this.lpNamesValue
    const data      = this.heatmapDataValue

    if (!data.length) return

    // All positive FMV values sorted ascending — basis for percentile rank
    const vals = data.map(d => d.value).filter(v => v > 0).sort((a, b) => a - b)
    const n    = vals.length

    // Returns 0–100 percentile rank so the gradient always spreads evenly
    // regardless of how skewed the raw dollar distribution is.
    const rankOf = v => {
      if (n <= 1) return 50
      if (v <= vals[0])   return 0
      if (v >= vals[n-1]) return 100
      const idx = vals.findIndex(x => x >= v)
      return Math.round((idx < 0 ? n - 1 : idx) / (n - 1) * 100)
    }

    // Pastel-green (rank 0) → forest-green (rank 100) via HSL lightness
    const rankToColor = rank => `hsl(142, 71%, ${(95 - rank * 0.75).toFixed(1)}%)`

    const fmtV = v => {
      if (v >= 1e9) return (v / 1e9).toFixed(1) + "B"
      if (v >= 1e6) return (v / 1e6).toFixed(1) + "M"
      if (v >= 1e3) return Math.round(v / 1e3) + "K"
      return Math.round(v).toString()
    }

    // Build [row][col] → value lookup
    const grid = {}
    data.forEach(d => {
      if (!grid[d.y]) grid[d.y] = {}
      grid[d.y][d.x] = d.value
    })

    const cellH = Math.max(24, Math.min(40, Math.floor(500 / Math.max(lps.length, 1))))
    const nameW = lps.reduce((m, nm) => Math.max(m, nm.length), 0) * 7 + 16
    const title = this.titleValue || "LP Exposure by Portfolio Company (Implied FMV)"

    // CSS Grid: fixed LP-name column, then equal-width fund columns (1fr each).
    // Avoids the browser's table auto-layout from misallocating column widths.
    const gridCols = `${nameW}px repeat(${companies.length}, 1fr)`
    const cellStyle = `display:flex;align-items:center;justify-content:center;min-height:${cellH}px;font-size:9px`

    let html = `<div style="font-size:13px;font-weight:600;margin-bottom:8px">${title}</div>
<div style="overflow-x:auto">
<div style="display:grid;grid-template-columns:${gridCols};gap:1px;background:#e5e7eb;border:1px solid #e5e7eb">
  <div style="background:#fff"></div>`

    companies.forEach(name => {
      html += `
  <div style="background:#fff;padding:4px;min-height:48px;display:flex;align-items:center;justify-content:center;text-align:center;overflow:hidden">
    <span style="font-weight:700;font-size:11px;word-break:break-word;line-height:1.2">${name}</span>
  </div>`
    })

    lps.forEach((lp, y) => {
      html += `
  <div style="background:#fff;${cellStyle};justify-content:flex-end;padding:0 8px 0 0;white-space:nowrap;font-weight:600;font-size:11px">${lp}</div>`
      companies.forEach((co, x) => {
        const v = (grid[y] || {})[x]
        if (v != null) {
          const rank  = rankOf(v)
          const bg    = rankToColor(rank)
          const fg    = rank > 55 ? "#fff" : "#1a1a1a"
          const tip   = `${lp} → ${co}: ${currency} ${Math.round(v).toLocaleString()}`
          html += `
  <div title="${tip}" style="background:${bg};color:${fg};cursor:default;${cellStyle}">${fmtV(v)}</div>`
        } else {
          html += `
  <div style="background:#F3F4F6;min-height:${cellH}px"></div>`
        }
      })
    })

    html += `\n</div></div>`

    // Gradient legend showing actual FMV at min → max
    html += `
<div style="margin-top:8px;display:flex;align-items:center;gap:6px;font-size:9px;color:#666">
  <span>${fmtV(vals[0])}</span>
  <div style="width:140px;height:8px;background:linear-gradient(to right,hsl(142,71%,95%),hsl(142,71%,57.5%),hsl(142,71%,20%));border-radius:2px;flex-shrink:0"></div>
  <span>${fmtV(vals[n - 1])}</span>
</div>`

    this.heatmapTarget.innerHTML = html
  }
}
