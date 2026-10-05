// NDA Status dashboard Stimulus controller.
// Handles client-side status filtering, text search, and exemption grant/revoke actions.
// Changed: New controller for Module 3 GP Dashboard.
// Why: The dashboard uses a server-rendered HTML table; filtering and search
//   are client-side to avoid round-trips, while exemption actions hit the server.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["statusFilter", "searchInput", "tableBody", "row"]
  static values = { ndaConfigId: Number, folderId: Number }

  // Filters visible rows by status dropdown and search input combined.
  filterRows() {
    const status = this.statusFilterTarget.value.toLowerCase()
    const query = this.searchInputTarget.value.toLowerCase().trim()

    this.rowTargets.forEach(row => {
      const rowStatus = (row.dataset.status || "").toLowerCase()
      const investorName = (row.dataset.investorName || "")

      const matchesStatus = !status || rowStatus === status
      const matchesSearch = !query || investorName.includes(query)

      // Changed: Also hide the collapsible user-detail row that follows each investor row.
      // Why: If the investor row is hidden by filter, its detail row should hide too.
      const nextRow = row.nextElementSibling
      if (matchesStatus && matchesSearch) {
        row.style.display = ""
        if (nextRow && nextRow.querySelector("table")) nextRow.style.display = ""
      } else {
        row.style.display = "none"
        if (nextRow && nextRow.querySelector("table")) nextRow.style.display = "none"
      }
    })
  }

  filterByStatus() {
    this.filterRows()
  }

  search() {
    this.filterRows()
  }

  // Grants an NDA exemption for a user. Reloads page on success.
  async grantExemption(event) {
    const button = event.currentTarget
    const userId = button.dataset.userId
    const userName = button.dataset.userName
    const reason = prompt(`Reason for exempting ${userName} (optional):`)

    if (reason === null) return

    try {
      const response = await fetch("/nda_status/exemptions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
        },
        body: JSON.stringify({
          nda_config_id: this.ndaConfigIdValue,
          user_id: userId,
          reason: reason
        })
      })

      if (response.ok) {
        window.location.reload()
      } else {
        const data = await response.json()
        alert(data.error || "Failed to create exemption")
      }
    } catch (e) {
      alert("Network error — please try again")
    }
  }

  // Changed: Added tagSignatory action for per-NDA signatory designation.
  // Why: Replaces entity-wide InvestorAccess tag_list with per-NDA signatory tagging.
  async tagSignatory(event) {
    const button = event.currentTarget
    const userId = button.dataset.userId
    const userName = button.dataset.userName

    if (!confirm(`Tag ${userName} as a designated NDA signatory?`)) return

    try {
      const response = await fetch("/nda_status/signatories", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
        },
        body: JSON.stringify({
          nda_config_id: this.ndaConfigIdValue,
          user_id: userId
        })
      })

      if (response.ok) {
        window.location.reload()
      } else {
        const data = await response.json()
        alert(data.error || "Failed to tag signatory")
      }
    } catch (e) {
      alert("Network error — please try again")
    }
  }

  // Changed: Added untagSignatory action to remove per-NDA signatory designation.
  // Why: Replaces entity-wide InvestorAccess tag_list with per-NDA signatory tagging.
  async untagSignatory(event) {
    const button = event.currentTarget
    const signatoryId = button.dataset.signatoryId
    const userName = button.dataset.userName

    if (!confirm(`Remove signatory designation for ${userName}?`)) return

    try {
      const response = await fetch(`/nda_status/signatories/${signatoryId}`, {
        method: "DELETE",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
        },
        body: JSON.stringify({ nda_config_id: this.ndaConfigIdValue })
      })

      if (response.ok) {
        window.location.reload()
      } else {
        const data = await response.json()
        alert(data.error || "Failed to untag signatory")
      }
    } catch (e) {
      alert("Network error — please try again")
    }
  }

  // Revokes an NDA exemption. Reloads page on success.
  async revokeExemption(event) {
    const button = event.currentTarget
    const exemptionId = button.dataset.exemptionId
    const userName = button.dataset.userName

    if (!confirm(`Revoke NDA exemption for ${userName}?`)) return

    try {
      const response = await fetch(`/nda_status/exemptions/${exemptionId}`, {
        method: "DELETE",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
        },
        body: JSON.stringify({ nda_config_id: this.ndaConfigIdValue })
      })

      if (response.ok) {
        window.location.reload()
      } else {
        const data = await response.json()
        alert(data.error || "Failed to revoke exemption")
      }
    } catch (e) {
      alert("Network error — please try again")
    }
  }
}
