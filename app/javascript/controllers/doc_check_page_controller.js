import { Controller } from "@hotwired/stimulus"

// Settings → Document Checks:
// - a document's side panel: "Fill in / Compare / Ask yes-no" add a check of that kind; picking a KYC field
//   fills "Look for" with its label (unless the user typed their own); a field already used on the
//   document is greyed out in its other checks; the panel re-opens itself after a refused save
// - Suggested checks: a document's tick toggles its rows, and the Add button counts what is ticked
// - Test on a KYC stays disabled until a KYC is picked (the picker is a select2, which fires jQuery change)
// openspec/changes/document-checks/design.md (card ① Setup, Build notes). Journeys J3.1–J3.4.
export default class extends Controller {
  static targets = ["rows", "addButton", "trialPicker", "trialButton"]
  static values = { open: String }

  connect() {
    this.counter = 0
    this.element.querySelectorAll("[data-doc-check-panel]").forEach((panel) => this.refreshUsedFields(panel))
    this.countPicks()
    this.watchTrialPicker()
    this.reopenPanel()
  }

  disconnect() {
    if (this.hasTrialPickerTarget && window.jQuery) window.jQuery(this.trialPickerTarget).off("change.docCheck")
  }

  // After a refused save the page comes back with the errors in that document's panel: show it again
  reopenPanel() {
    if (!this.openValue) return
    const panel = document.getElementById(this.openValue)
    if (!panel || !window.bootstrap?.Offcanvas) return
    panel.classList.remove("show")
    window.bootstrap.Offcanvas.getOrCreateInstance(panel).show()
  }

  // ── A document's checks ───────────────────────────────────────────────────

  addCheck(event) {
    const panel = event.currentTarget.closest("[data-doc-check-panel]")
    const kind = event.currentTarget.dataset.kind
    const key = `n${Date.now()}${this.counter++}`
    const template = panel.querySelector(`template[data-role='template-${kind}']`)
    const list = panel.querySelector("[data-role='checks']")
    list.insertAdjacentHTML("beforeend", template.innerHTML.replaceAll("__KEY__", key))
    panel.querySelector("[data-role='empty']")?.classList.add("d-none")
    const check = list.lastElementChild
    this.refreshUsedFields(panel)
    check.scrollIntoView({ behavior: "smooth", block: "nearest" })
    ;(check.querySelector("[data-role='field']") || check.querySelector("[data-role='look-for']"))?.focus()
  }

  removeRow(event) {
    const panel = event.target.closest("[data-doc-check-panel]")
    event.target.closest("[data-doc-check-page-target='row']").remove()
    if (!panel.querySelector("[data-doc-check-page-target='row']")) panel.querySelector("[data-role='empty']")?.classList.remove("d-none")
    this.refreshUsedFields(panel)
  }

  // Fill "Look for" from the field's label when it is empty or still holds the previous field's label
  fieldChanged(event) {
    const select = event.target
    const check = select.closest("[data-doc-check-page-target='row']")
    const lookFor = check.querySelector("[data-role='look-for']")
    const label = select.selectedOptions[0]?.dataset.label || ""
    const previous = check.dataset.autoLabel || ""
    if (lookFor && (lookFor.value.trim() === "" || lookFor.value === previous)) {
      lookFor.value = label
      check.dataset.autoLabel = label
    }
    this.refreshUsedFields(select.closest("[data-doc-check-panel]"))
  }

  // Grey out, in each check of a document, the fields its other checks already use
  refreshUsedFields(panel) {
    if (!panel) return
    const selects = Array.from(panel.querySelectorAll("[data-role='checks'] [data-role='field']"))
    const used = selects.map((s) => s.value).filter((v) => v !== "")
    selects.forEach((select) => {
      Array.from(select.options).forEach((option) => {
        if (option.value === "") return
        const takenElsewhere = used.includes(option.value) && option.value !== select.value
        option.disabled = takenElsewhere
        const label = option.dataset.label || option.textContent
        option.textContent = takenElsewhere ? `${label} (already used on this document)` : label
      })
    })
  }

  // ── Suggested checks ──────────────────────────────────────────────────────

  toggleDocument(event) {
    const block = event.target.closest(".doc-check-recommendation")
    block.querySelectorAll("[data-role='pick']").forEach((box) => { box.checked = event.target.checked })
    this.countPicks()
  }

  countPicks() {
    if (!this.hasAddButtonTarget) return
    const boxes = Array.from(this.element.querySelectorAll("[data-role='pick']"))
    const count = boxes.filter((box) => box.checked).length
    this.addButtonTarget.disabled = count === 0
    this.addButtonTarget.textContent = count === 1 ? "Add 1 check" : `Add ${count} checks`
    // A document's own tick follows its rows
    this.element.querySelectorAll(".doc-check-recommendation").forEach((block) => {
      const picks = Array.from(block.querySelectorAll("[data-role='pick']"))
      const head = block.querySelector("input[data-action='doc-check-page#toggleDocument']")
      if (head) head.checked = picks.some((box) => box.checked)
    })
  }

  // ── Test on a KYC ─────────────────────────────────────────────────────────

  watchTrialPicker() {
    if (!this.hasTrialPickerTarget) return
    const update = () => { this.trialButtonTarget.disabled = this.trialPickerTarget.value === "" }
    update()
    this.trialPickerTarget.addEventListener("change", update)
    if (window.jQuery) window.jQuery(this.trialPickerTarget).on("change.docCheck", update)
  }
}
