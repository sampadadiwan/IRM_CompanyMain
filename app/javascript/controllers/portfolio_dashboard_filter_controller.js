import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["search", "statusFilter", "tableBody", "tableFrame"]

  tableFrameTargetConnected(frame) {
    frame.addEventListener("turbo:frame-load", () => {
      frame.scrollIntoView({ behavior: "smooth", block: "start" })
    })
  }

  filter() {
    const query = this.hasSearchTarget ? this.searchTarget.value.toLowerCase() : ""
    const status = this.hasStatusFilterTarget ? this.statusFilterTarget.value : ""
    const rows = this.tableBodyTarget.querySelectorAll("tr[data-status]")

    rows.forEach(row => {
      const detailRow = row.nextElementSibling
      const matchesSearch = !query || row.dataset.company.includes(query)
      const matchesStatus = !status || row.dataset.status === status
      const visible = matchesSearch && matchesStatus

      row.style.display = visible ? "" : "none"
      if (detailRow && detailRow.classList.contains("collapse")) {
        detailRow.style.display = visible ? "" : "none"
      }
    })
  }

  filterByStatus(event) {
    const status = event.params.status

    if (status === "submitted") {
      if (this.hasStatusFilterTarget) this.statusFilterTarget.value = ""
      this._filterCustom(row => row.dataset.status === "Complete" || row.dataset.status === "Incomplete")
      return
    }

    if (status === "issues") {
      if (this.hasStatusFilterTarget) this.statusFilterTarget.value = ""
      this._filterCustom(row => parseInt(row.dataset.issues || "0", 10) > 0)
      return
    }

    if (this.hasStatusFilterTarget) this.statusFilterTarget.value = status
    this.filter()
  }

  statusDropdownChange(event) {
    const url = event.target.value
    const fallback = event.target.dataset.fallbackUrl
    Turbo.visit(url || fallback, { frame: "portfolio_table_frame" })
  }

  filterPending() {
    if (this.hasStatusFilterTarget) this.statusFilterTarget.value = "Incomplete"
    this.filter()
  }

  _filterCustom(predicate) {
    const query = this.hasSearchTarget ? this.searchTarget.value.toLowerCase() : ""
    const rows = this.tableBodyTarget.querySelectorAll("tr[data-status]")

    rows.forEach(row => {
      const detailRow = row.nextElementSibling
      const matchesSearch = !query || row.dataset.company.includes(query)
      const matchesPredicate = predicate(row)
      const visible = matchesSearch && matchesPredicate

      row.style.display = visible ? "" : "none"
      if (detailRow && detailRow.classList.contains("collapse")) {
        detailRow.style.display = visible ? "" : "none"
      }
    })
  }
}
