import { Controller } from "@hotwired/stimulus"

// Handles inline editing for PortfolioReportDraft show page.
//
// KPI cell  — click a td, replace with number input, PATCH update_kpi_cell on blur
// Section   — double-click the narrative-display div to open a Trix rich-text editor.
//             Save/Cancel buttons control saving and dismissal.
//
// Values:
//   kpi-cell-url  — PATCH url for update_kpi_cell
//   section-url   — PATCH url for update_section
//   editable      — false = read-only (approved/exported status)
export default class extends Controller {
  static targets = ["savedBadge"]
  static values  = { kpiCellUrl: String, sectionUrl: String, editable: Boolean }

  // ── KPI cell (click) ─────────────────────────────────────────────────────

  editKpiCell(event) {
    if (!this.editableValue) return
    const td = event.currentTarget
    if (td.querySelector("input")) return   // already editing

    const metricId    = td.dataset.metricId
    const periodLabel = td.dataset.periodLabel
    const original    = td.textContent.trim()
    const currentVal  = parseFloat(original) || 0

    const input       = document.createElement("input")
    input.type        = "number"
    input.value       = currentVal
    input.step        = "any"
    input.className   = "form-control form-control-sm text-end"
    input.style.width = "90px"

    td.textContent = ""
    td.appendChild(input)
    input.focus()
    input.select()

    const save = async () => {
      const value = input.value.trim()
      td.textContent = value || original
      await this.#patch(this.kpiCellUrlValue, { metric_id: metricId, period_label: periodLabel, value })
    }

    input.addEventListener("blur", save, { once: true })
    input.addEventListener("keydown", e => {
      if (e.key === "Enter")  { e.preventDefault(); input.blur() }
      if (e.key === "Escape") {
        input.removeEventListener("blur", save)
        td.textContent = original
      }
    })
  }

  // ── Section narrative — open Trix editor ─────────────────────────────────

  editSection(event) {
    if (!this.editableValue) return
    const display   = event.currentTarget
    const sectionId = display.dataset.sectionId
    const cardBody  = display.closest(".card-body")
    const editor    = cardBody.querySelector(`.narrative-editor[data-section-id="${sectionId}"]`)
    if (!editor) return

    display.classList.add("d-none")
    editor.classList.remove("d-none")
    editor.querySelector("trix-editor")?.focus()
  }

  // ── Save Trix content ─────────────────────────────────────────────────────

  async saveSection(event) {
    const sectionId = event.currentTarget.dataset.sectionId
    const cardBody  = event.currentTarget.closest(".card-body")
    const display   = cardBody.querySelector(`.narrative-display[data-section-id="${sectionId}"]`)
    const editor    = cardBody.querySelector(`.narrative-editor[data-section-id="${sectionId}"]`)
    const html      = document.getElementById(`trix-input-${sectionId}`)?.value ?? ""

    // Optimistic update: swap editor out before the network round-trip
    display.innerHTML = html
    editor.classList.add("d-none")
    display.classList.remove("d-none")

    await this.#patch(this.sectionUrlValue, { section_id: sectionId, text: html })
  }

  // ── Cancel edit ───────────────────────────────────────────────────────────

  cancelSection(event) {
    const sectionId = event.currentTarget.dataset.sectionId
    const cardBody  = event.currentTarget.closest(".card-body")
    const display   = cardBody.querySelector(`.narrative-display[data-section-id="${sectionId}"]`)
    const editor    = cardBody.querySelector(`.narrative-editor[data-section-id="${sectionId}"]`)

    editor.classList.add("d-none")
    display.classList.remove("d-none")
  }

  // ── Private ──────────────────────────────────────────────────────────────

  async #patch(url, body) {
    try {
      const res = await fetch(url, {
        method:  "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
        },
        body: JSON.stringify(body)
      })
      if (res.ok) this.#showSaved()
      else console.error(`[DraftEditor] save failed: ${res.status}`)
    } catch (err) {
      console.error("[DraftEditor] Network error:", err)
    }
  }

  #showSaved() {
    if (!this.hasSavedBadgeTarget) return
    this.savedBadgeTarget.classList.remove("d-none")
    setTimeout(() => this.savedBadgeTarget.classList.add("d-none"), 2500)
  }
}
