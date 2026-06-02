import { Controller } from "@hotwired/stimulus"

// Inline step-through walkthrough for account entry formula explanations.
// Steps array includes a leading "summary" entry and a trailing "conclusion"
// entry that show context without an expression/value pair.
export default class extends Controller {
  static targets = [
    "panel",
    "stepNum", "stepTotal",
    "expressionSection",  // hidden for summary/conclusion steps
    "valueSection",       // hidden for summary/conclusion steps
    "expression", "value", "meaning", "meaningLabel",
    "prevBtn", "nextBtn",
    "progressBar"
  ]
  static values = {
    steps: Array,
    formula: String,
    summary: String,
    conclusion: String
  }

  connect() {
    this._sidebarBtns = Array.from(this.element.querySelectorAll("[data-step-index]"))
    this._activeBtn   = null
    this._tableRows   = Array.from(this.element.querySelectorAll("[data-step-expr]"))
    this.index        = 0
  }

  toggle() {
    if (!this.hasPanelTarget) return
    // Walkthrough panel is desktop-only — matches the d-none d-lg-inline-flex on the button
    if (window.innerWidth < 992) return
    const hidden = this.panelTarget.classList.toggle("d-none")
    if (!hidden) {
      this.render()
      this.panelTarget.scrollIntoView({ behavior: "smooth", block: "nearest" })
    } else {
      this._clearTableHighlight()
    }
  }

  prev() {
    if (this.index > 0) { this.index--; this.render() }
  }

  next() {
    if (this.index < this.stepsValue.length - 1) { this.index++; this.render() }
  }

  jumpTo(event) {
    const i = parseInt(event.currentTarget.dataset.stepIndex, 10)
    if (!isNaN(i)) { this.index = i; this.render() }
  }

  render() {
    const steps = this.stepsValue
    const total = steps.length
    const step  = steps[this.index]
    if (!step) return

    // Progress
    this.stepNumTarget.textContent   = this.index + 1
    this.stepTotalTarget.textContent = total
    const pct = Math.round(((this.index + 1) / total) * 100)
    this.progressBarTarget.style.width = `${pct}%`
    this.progressBarTarget.setAttribute("aria-valuenow", pct)

    // Summary/conclusion steps have no expression or value — hide those rows
    const isSpecial = step.type === "summary" || step.type === "conclusion"
    if (this.hasExpressionSectionTarget) {
      this.expressionSectionTarget.style.display = isSpecial ? "none" : ""
    }
    if (this.hasValueSectionTarget) {
      this.valueSectionTarget.style.display = isSpecial ? "none" : ""
    }

    // Meaning label reflects the step type
    if (this.hasMeaningLabelTarget) {
      this.meaningLabelTarget.textContent =
        step.type === "summary"    ? "Summary"    :
        step.type === "conclusion" ? "Conclusion" :
        "What this means"
    }

    this.expressionTarget.textContent = step.expression || ""
    this.valueTarget.textContent      = step.value      || ""
    this.meaningTarget.textContent    = step.meaning    || ""

    this.prevBtnTarget.disabled = this.index === 0
    this.nextBtnTarget.disabled = this.index === total - 1

    // Sidebar active state
    if (this._activeBtn) this._activeBtn.classList.remove("active", "fw-bold", "text-primary")
    this._activeBtn = this._sidebarBtns[this.index]
    if (this._activeBtn) this._activeBtn.classList.add("active", "fw-bold", "text-primary")

    // Table row highlight — cleared for summary/conclusion (no matching row)
    isSpecial ? this._clearTableHighlight() : this._highlightTableRow(step.expression)
  }

  _highlightTableRow(expression) {
    let activeRow = null
    this._tableRows.forEach(row => {
      const match = row.dataset.stepExpr === expression
      row.classList.toggle("table-warning", match)
      if (match) activeRow = row
    })
    if (activeRow) activeRow.scrollIntoView({ block: "nearest", behavior: "smooth" })
  }

  _clearTableHighlight() {
    this._tableRows.forEach(row => row.classList.remove("table-warning"))
  }
}
