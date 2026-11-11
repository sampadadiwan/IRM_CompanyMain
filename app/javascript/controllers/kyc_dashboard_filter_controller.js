/**
 * Stimulus controller for KYC Dashboard stat card filtering.
 * Manages active state on stat cards and submits Turbo Frame requests
 * with status + kyc_type filters to reload the table. Cards in the
 * Individual / Non-Individual columns pass their STI type so the table
 * filters to both status and KYC type simultaneously.
 */
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["statCard", "statsRow"]

  /**
   * Handles stat card click — toggles the active card and reloads the table
   * with the selected status + kyc_type filter via Turbo Frame navigation.
   */
  filterByCard(event) {
    const clickedCard = event.currentTarget
    const status = event.params.status
    const kycType = event.params.kycType
    const isActive = clickedCard.classList.contains("border-3")

    this.statCardTargets.forEach(card => {
      card.classList.remove("border-3", "shadow")
    })

    if (isActive) {
      this._reloadTable("", "")
    } else {
      clickedCard.classList.add("border-3", "shadow")
      this._reloadTable(status, kycType)
    }
  }

  /**
   * Reloads the KYC dashboard table Turbo Frame with status and kyc_type params.
   * @param {string} status - agent status bucket (validated, pending, etc.)
   * @param {string} kycType - STI type (IndividualKyc / NonIndividualKyc)
   */
  _reloadTable(status, kycType) {
    const frame = document.getElementById("kyc-dashboard-table")
    if (!frame) return

    const url = new URL(window.location.href)

    if (status) {
      url.searchParams.set("status", status)
    } else {
      url.searchParams.delete("status")
    }

    if (kycType) {
      url.searchParams.set("kyc_type", kycType)
    } else {
      url.searchParams.delete("kyc_type")
    }

    url.searchParams.set("tab", "kyc_dashboard")
    frame.src = url.toString()

    // Scroll to the table so filtered results are visible after card click
    frame.scrollIntoView({ behavior: "smooth", block: "start" })
  }
}
