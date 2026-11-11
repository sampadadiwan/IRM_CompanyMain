/**
 * Stimulus controller for the KYC run output inline detail panel.
 * Shows the parent detail <tr> on connect (when Turbo loads the panel),
 * highlights the associated KYC row, and hides the detail row on close.
 * Also handles item tab filtering (show/hide rows by data-status).
 */
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["itemsBody"]
  static values = { kycId: Number }

  connect() {
    this._showDetailRow()
    this._highlightRow()
  }

  disconnect() {
    this._clearHighlight()
  }

  /** Closes the panel by hiding the detail row and clearing the frame. */
  close() {
    this._clearHighlight()
    this._hideDetailRow()
  }

  /**
   * Filters item rows by the selected tab (all, passed, failed, warning,
   * documents). The "documents" tab filters by data-source="document" instead
   * of data-status, showing only document validation items.
   * Hides step groups that have no visible rows after filtering.
   */
  filterItems(event) {
    event.preventDefault()
    const tab = event.params.tab

    const tabs = this.element.querySelectorAll(".nav-link")
    tabs.forEach(t => t.classList.remove("active"))
    event.currentTarget.classList.add("active")

    if (!this.hasItemsBodyTarget) return
    const rows = this.itemsBodyTarget.querySelectorAll("tr[data-status]")

    rows.forEach(row => {
      if (tab === "all") {
        row.style.display = ""
      } else if (tab === "documents") {
        row.style.display = row.dataset.source === "document" ? "" : "none"
      } else {
        row.style.display = row.dataset.status === tab ? "" : "none"
      }
    })

    // Hide step groups with no visible rows
    this.itemsBodyTarget.querySelectorAll("[data-step]").forEach(group => {
      const visibleRows = group.querySelectorAll("tr[data-status]")
      const hasVisible = Array.from(visibleRows).some(r => r.style.display !== "none")
      group.style.display = hasVisible ? "" : "none"
    })
  }

  /** @private Shows the detail <tr> that contains this panel. */
  _showDetailRow() {
    if (!this.hasKycIdValue) return
    const detailRow = document.querySelector(`tr[data-kyc-detail-for="${this.kycIdValue}"]`)
    if (detailRow) detailRow.classList.remove("d-none")
  }

  /** @private Hides the detail <tr> and clears its turbo frame content. */
  _hideDetailRow() {
    if (!this.hasKycIdValue) return
    const detailRow = document.querySelector(`tr[data-kyc-detail-for="${this.kycIdValue}"]`)
    if (detailRow) {
      detailRow.classList.add("d-none")
      const frame = detailRow.querySelector("turbo-frame")
      if (frame) frame.innerHTML = ""
    }
  }

  /** @private Highlights the table row matching the open report's KYC ID. */
  _highlightRow() {
    if (!this.hasKycIdValue) return
    this._clearHighlight()
    const row = document.querySelector(`tr[data-kyc-id="${this.kycIdValue}"]`)
    if (row) row.classList.add("table-active")
  }

  /** @private Removes highlight from all table rows. */
  _clearHighlight() {
    document.querySelectorAll("tr.table-active[data-kyc-id]").forEach(r => r.classList.remove("table-active"))
  }
}
