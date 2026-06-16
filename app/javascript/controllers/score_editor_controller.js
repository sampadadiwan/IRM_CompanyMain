import InlineEditorController from "controllers/inline_editor_controller"

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

  // Dimension scores feed the row's contribution and the overall score, neither
  // of which re-render on their own — recompute them optimistically on edit.
  onFieldChanged(el) {
    if (el.dataset.dimField === "score") return this.#syncDimension(el)
    if (el.dataset.field === "overall_score") return this.#syncOverallBar(parseInt(el.textContent.trim()) || 0)
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

  // A dimension exists twice in the DOM (desktop row + mobile card), sharing
  // data-dimension-index — push the new score to both so collectPayload (which
  // only reads the first copy) never sees a stale value from the untouched one.
  #syncDimension(scoreEl) {
    const container = scoreEl.closest("[data-dimension-index]")
    if (!container) return

    const idx     = container.dataset.dimensionIndex
    const weight  = parseFloat(container.dataset.dimWeight) || 0
    const score   = Math.min(100, Math.max(0, parseInt(scoreEl.textContent.trim()) || 0))
    const contrib = this.#round1(score * weight)
    const barClass = this.#scoreBarClass(score)

    this.element.querySelectorAll(`[data-dimension-index="${idx}"]`).forEach(c => {
      c.querySelectorAll('[data-dim-field="score"]').forEach(el => {
        el.textContent = el.closest(".d-md-none") ? `${score} / 100` : String(score)
        this.#swapBarClass(el, barClass)
      })
      c.querySelectorAll('[data-dim-field="score-bar"]').forEach(bar => {
        bar.style.width = `${score}%`
        bar.setAttribute("aria-valuenow", score)
        bar.textContent = score
        this.#swapBarClass(bar, barClass)
      })
      c.querySelectorAll('[data-dim-field="contribution"]').forEach(el => {
        el.textContent = contrib
        if (el.classList.contains("badge")) this.#swapBarClass(el, barClass)
      })
    })

    this.#recalculateOverall()
  }

  // Sums every dimension's contribution exactly once (desktop + mobile share an
  // index) and pushes the total into the footer totals and the headline score.
  #recalculateOverall() {
    const seen = new Set()
    let total = 0

    this.element.querySelectorAll("[data-dimension-index]").forEach(c => {
      const idx = c.dataset.dimensionIndex
      if (seen.has(idx)) return
      seen.add(idx)

      const weight  = parseFloat(c.dataset.dimWeight) || 0
      const scoreEl = c.querySelector('[data-dim-field="score"]')
      const score   = parseInt(scoreEl?.textContent.trim()) || 0
      total += score * weight
    })

    total = this.#round1(total)
    this.element.querySelectorAll('[data-field="computed_total"]').forEach(el => { el.textContent = total })

    const overallEl = this.element.querySelector('[data-field="overall_score"]')
    if (overallEl) overallEl.textContent = Math.round(total)

    this.#syncOverallBar(Math.round(total))
  }

  #syncOverallBar(value) {
    const bar = this.element.querySelector('[data-field="overall_score_bar"]')
    if (!bar) return
    bar.style.width = `${value}%`
    bar.setAttribute("aria-valuenow", value)
    bar.textContent = value
    this.#swapBarClass(bar, this.#scoreBarClass(value))
  }

  #scoreBarClass(score) {
    if (score >= 80) return "bg-success"
    if (score >= 60) return "bg-primary"
    if (score >= 40) return "bg-warning"
    return "bg-danger"
  }

  #swapBarClass(el, barClass) {
    el.classList.remove("bg-success", "bg-primary", "bg-warning", "bg-danger")
    el.classList.add(barClass)
  }

  // Matches Ruby's Float#round(1) (round-half-up); nudges away the binary
  // float error that 0.15/0.2/0.25-style weights introduce (e.g. 17.5000000002).
  #round1(n) {
    return Math.round((n + Number.EPSILON) * 10) / 10
  }
}
