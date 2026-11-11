/**
 * Disables the Re-run Agent button after form submission, highlights the
 * source table row, and re-enables both when the progress panel finishes
 * (status changes from Running to completed).
 */
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this._btn = this.element.querySelector("button[type='submit']")
    this._originalHTML = this._btn?.innerHTML
  }

  disable() {
    if (!this._btn) return
    this._btn.disabled = true
    this._btn.innerHTML = '<i class="spinner-border spinner-border-sm"></i>'

    // Highlight the table row being run
    this._highlightRow()

    // Clear any stale progress panel from a prior run so old ActionCable
    // broadcasts (which target unscoped step IDs like step_1) cannot
    // overwrite the incoming panel for this run.
    const panel = document.getElementById("kyc_single_progress_panel")
    if (panel) panel.innerHTML = ""

    // Watch the progress panel — re-enable when run completes
    this._watchPanel()
  }

  _highlightRow() {
    // Remove highlight from any previously highlighted row
    document.querySelectorAll("tr.table-active").forEach(r => r.classList.remove("table-active"))
    // Highlight the row containing this button's form
    this._row = this.element.closest("tr")
    if (this._row) this._row.classList.add("table-active")
  }

  _watchPanel() {
    const panel = document.getElementById("kyc_single_progress_panel")
    if (!panel) return

    this._panelObserver = new MutationObserver(() => {
      const badge = panel.querySelector("#status_badge_new, [id^='status_badge_']")
      const text = badge?.textContent?.trim() || ""
      // Re-enable when status is no longer "Running"
      if (text && !text.includes("Running")) {
        this._reenable()
        this._panelObserver?.disconnect()
      }
    })
    this._panelObserver.observe(panel, { childList: true, subtree: true, characterData: true })
  }

  _reenable() {
    if (!this._btn) return
    this._btn.disabled = false
    this._btn.innerHTML = this._originalHTML

    // Remove row highlight
    if (this._row) this._row.classList.remove("table-active")

    // Full page reload is handled by support_agent_progress_controller
    // after the progress panel broadcasts completion — no need to
    // separately reload the table frame here.
  }

  disconnect() {
    this._panelObserver?.disconnect()
  }
}
