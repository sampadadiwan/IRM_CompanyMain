import InlineEditorController from "./inline_editor_controller"

// Inline editor for PortfolioScoringAgent scorecards.
// Extends InlineEditorController — all DOM interaction lives in the base class.
// This subclass only knows the scorecard JSON shape.
export default class extends InlineEditorController {
  static values = { url: String, editable: Boolean, reportId: Number }

  get editableSelector() {
    return "[data-field], [data-dim-field], [data-dim-list], li[data-list]"
  }

  isNumberField(el) {
    return el.dataset.field === "overall_score" || el.dataset.dimField === "score"
  }

  collectPayload() {
    return { report_id: this.reportIdValue, score: this.#collectScore() }
  }

  // ── Private ──────────────────────────────────────────────────────────────

  #collectScore() {
    const score = {}

    // Scalar fields: overall_score, grade, summary
    this.element.querySelectorAll("[data-field]").forEach(el => {
      const f   = el.dataset.field
      const raw = el.textContent.trim()
      score[f]  = (f === "overall_score") ? (parseInt(raw) || 0) : raw
    })

    // Dimensions — desktop table rows and mobile cards both carry data-dimension-index;
    // skip duplicates via a seen-set so mobile cards don't double-count.
    const seen = new Set()
    score["dimensions"] = []

    this.element.querySelectorAll("[data-dimension-index]").forEach(container => {
      const idx = container.dataset.dimensionIndex
      if (seen.has(idx)) return
      seen.add(idx)

      const dim     = {}
      dim["name"]   = container.dataset.dimName
      dim["weight"] = parseFloat(container.dataset.dimWeight) || 0

      container.querySelectorAll("[data-dim-field]").forEach(el => {
        const f  = el.dataset.dimField
        const raw = el.textContent.trim()
        dim[f]   = (f === "score") ? (parseInt(raw) || 0) : raw
      })

      dim["positives"] = Array.from(container.querySelectorAll("[data-dim-list='positives']"))
        .map(li => li.textContent.trim()).filter(Boolean)
      dim["concerns"]  = Array.from(container.querySelectorAll("[data-dim-list='concerns']"))
        .map(li => li.textContent.trim()).filter(Boolean)

      score["dimensions"].push(dim)
    })

    // Top-level analysis lists (use first ul to avoid mobile duplicates)
    ;["strengths", "risks", "recommendations"].forEach(key => {
      const ul = this.element.querySelector(`ul[data-list='${key}']`)
      if (ul) {
        score[key] = Array.from(ul.querySelectorAll(`li[data-list='${key}']`))
          .map(li => li.textContent.trim()).filter(Boolean)
      }
    })

    return score
  }
}
