import { Controller } from "@hotwired/stimulus"

// Drives the generate-reports configure form:
// - populates the template dropdown when the report type changes
// - shows a "N periods found" preview badge when date/period fields change
export default class extends Controller {
  static targets = ["templateSelect", "kpiPreview"]
  static values  = { previewUrl: String }

  connect() {
    this.templatesData = JSON.parse(
      document.getElementById("report-templates-data")?.textContent || "{}"
    )
    // Debounce timer for the preview fetch
    this._previewTimer = null
  }

  reportChanged(event) {
    const reportId = event.target.value
    const templates = this.templatesData[reportId] || []

    this.templateSelectTarget.innerHTML = templates.length
      ? templates.map(t => `<option value="${t.id}">${t.name}</option>`).join("")
      : `<option value="">— no templates for this report type —</option>`
  }

  // Called by any period-related field (end_date, kpi_period_type, kpi_tag, n_periods)
  previewChanged() {
    clearTimeout(this._previewTimer)
    this._previewTimer = setTimeout(() => this._fetchPreview(), 400)
  }

  _fetchPreview() {
    if (!this.hasKpiPreviewTarget) return
    if (!this.previewUrlValue)      return

    const endDate    = this.element.querySelector("[name$='[end_date]'], [name='end_date']")?.value
    const periodType = this.element.querySelector("[name$='[kpi_period_type]'], [name='kpi_period_type']")?.value
    const kpiTag     = this.element.querySelector("[name$='[kpi_tag]'], [name='kpi_tag']")?.value
    const nPeriods   = this.element.querySelector("[name$='[n_periods]'], [name='n_periods']")?.value

    if (!endDate) return

    const url = new URL(this.previewUrlValue, window.location.origin)
    url.searchParams.set("end_date",        endDate)
    url.searchParams.set("kpi_period_type", periodType || "Monthly")
    url.searchParams.set("kpi_tag",         kpiTag     || "Actual")
    url.searchParams.set("n_periods",       nPeriods   || "6")

    this.kpiPreviewTarget.innerHTML = `<span class="text-muted small"><span class="spinner-grow spinner-grow-sm me-1" style="width:0.6rem;height:0.6rem;"></span>Checking…</span>`

    fetch(url, { headers: { "Accept": "application/json" } })
      .then(r => r.json())
      .then(({ count, requested, labels }) => {
        if (count === 0) {
          this.kpiPreviewTarget.innerHTML =
            `<span class="badge bg-danger">No KPI data found for this period</span>`
        } else if (count < requested) {
          this.kpiPreviewTarget.innerHTML =
            `<span class="badge bg-warning text-dark">${count} of ${requested} periods found — ` +
            `${labels.join(", ")}</span>`
        } else {
          this.kpiPreviewTarget.innerHTML =
            `<span class="badge bg-success">${count} periods found — ${labels.join(", ")}</span>`
        }
      })
      .catch(() => {
        this.kpiPreviewTarget.innerHTML = `<span class="text-muted small">Preview unavailable</span>`
      })
  }
}
