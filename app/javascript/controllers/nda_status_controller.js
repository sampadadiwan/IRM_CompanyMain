// NDA Status dashboard Stimulus controller.
// Handles client-side status filtering, text search, signatory tag/untag,
// revocation, and bulk reminder actions.
// Changed: Module 8 — added revokeAcceptance and sendReminders actions.
// Why: GP needs to revoke accepted NDAs and bulk-remind pending investors from the dashboard.
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

  // Changed: Module 8 — revokeAcceptance action with confirmation dialog and optional reason.
  // Why: GP can revoke an accepted investor's NDA from the dashboard. Creates append-only
  //   NdaAcceptance row (status: "revoked") and fires LP notification.
  async revokeAcceptance(event) {
    const button = event.currentTarget
    const investorId = button.dataset.investorId
    const investorName = button.dataset.investorName

    const reason = prompt(
      `Revoke NDA acceptance for ${investorName}?\n\nEnter an optional reason (or leave blank):`,
      ""
    )

    // Changed: prompt() returns null on Cancel, empty string on OK-with-no-text.
    // Why: null means the GP cancelled — do nothing. Empty string means proceed without reason.
    if (reason === null) return

    try {
      button.disabled = true
      const response = await fetch("/nda_status/revoke", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
        },
        body: JSON.stringify({
          nda_config_id: this.ndaConfigIdValue,
          investor_id: investorId,
          reason: reason || null
        })
      })

      if (response.ok) {
        window.location.reload()
      } else {
        const data = await response.json()
        alert(data.error || "Failed to revoke NDA acceptance")
        button.disabled = false
      }
    } catch (e) {
      alert("Network error — please try again")
      button.disabled = false
    }
  }

  // Changed: Module 8 — sendReminders action with confirmation dialog.
  // Why: GP can bulk-send NDA reminders to all pending investors' signatories.
  //   Enqueues NdaReminderJob in background. Shows count of users who will be emailed.
  async sendReminders(event) {
    const button = event.currentTarget

    if (!confirm("Send NDA reminders to all pending investors' signatories?")) return

    try {
      button.disabled = true
      const response = await fetch("/nda_status/send_reminders", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
        },
        body: JSON.stringify({
          nda_config_id: this.ndaConfigIdValue
        })
      })

      const data = await response.json()
      if (response.ok) {
        alert(data.message || "Reminders sent successfully")
        button.disabled = false
      } else {
        alert(data.error || "Failed to send reminders")
        button.disabled = false
      }
    } catch (e) {
      alert("Network error — please try again")
      button.disabled = false
    }
  }

}
