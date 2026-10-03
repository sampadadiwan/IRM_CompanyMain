import { Controller } from "@hotwired/stimulus"

// One Document Checks card on Settings → Document Checks. Keeps the card easy to get right:
// - "What to do" swaps the row's inputs in place (Fill in: field + Replace existing values;
//   Compare: field; Yes-no question: expected answer)
// - picking a KYC field fills "Look for" with its label, unless the user has typed their own
// - a field already used on this card is greyed out in the other rows' dropdowns
// - any change shows "Unsaved changes" + Save, and leaving the page asks first
// openspec/changes/document-checks/design.md (card ① Setup, Build notes). Journeys J3.1–J3.4.
export default class extends Controller {
  static targets = ["rows", "row", "template", "footer", "head"]
  static values = { dirty: Boolean }

  connect() {
    this.counter = 0
    this.leaveGuard = (event) => {
      if (!this.dirtyValue) return
      event.preventDefault()
      event.returnValue = ""
    }
    window.addEventListener("beforeunload", this.leaveGuard)
    this.refreshUsedFields()
    this.toggleFooter()
  }

  disconnect() {
    window.removeEventListener("beforeunload", this.leaveGuard)
  }

  // A new empty row from the <template>, with a key no other row has
  addRow() {
    const key = `n${Date.now()}${this.counter++}`
    const html = this.templateTarget.innerHTML.replaceAll("__KEY__", key)
    this.rowsTarget.insertAdjacentHTML("beforeend", html)
    const row = this.rowTargets[this.rowTargets.length - 1]
    this.headTarget.classList.remove("d-none")
    this.applyAction(row)
    this.refreshUsedFields()
    this.markDirty()
    row.querySelector("[data-role='field']")?.focus()
  }

  removeRow(event) {
    event.target.closest("tr").remove()
    this.refreshUsedFields()
    this.markDirty()
  }

  actionChanged(event) {
    this.applyAction(event.target.closest("tr"))
    this.refreshUsedFields()
  }

  // Fill "Look for" from the field's label when it is empty or still holds the previous field's label
  fieldChanged(event) {
    const select = event.target
    const row = select.closest("tr")
    const lookFor = row.querySelector("[data-role='look-for']")
    const label = select.selectedOptions[0]?.dataset.label || ""
    const previous = row.dataset.autoLabel || ""
    if (lookFor && (lookFor.value.trim() === "" || lookFor.value === previous)) {
      lookFor.value = label
      row.dataset.autoLabel = label
    }
    this.refreshUsedFields()
  }

  changed() {
    this.markDirty()
  }

  // Saving: the page is about to change on purpose
  submitting() {
    this.dirtyValue = false
  }

  applyAction(row) {
    const action = row.querySelector("[data-role='action']").value
    const question = action === "question"
    const fieldCell = row.querySelector("[data-role='field-cell']")
    const expectedCell = row.querySelector("[data-role='expected-cell']")
    const field = row.querySelector("[data-role='field']")
    fieldCell.classList.toggle("d-none", question)
    expectedCell.classList.toggle("d-none", !question)
    // A disabled select isn't posted: a question has no field
    field.disabled = question
    row.querySelector("[data-role='replace']")?.classList.toggle("d-none", action !== "fill_in")
    const lookFor = row.querySelector("[data-role='look-for']")
    if (lookFor) lookFor.placeholder = question ? "Question" : "Look for"
  }

  // Grey out, in every row, the fields other rows of this card already use
  refreshUsedFields() {
    const selects = this.rowTargets.map((row) => row.querySelector("[data-role='field']")).filter((s) => s && !s.disabled)
    const used = selects.map((s) => s.value).filter((v) => v !== "")
    selects.forEach((select) => {
      Array.from(select.options).forEach((option) => {
        if (option.value === "") return
        const takenElsewhere = used.includes(option.value) && option.value !== select.value
        option.disabled = takenElsewhere
        const label = option.dataset.label || option.textContent
        option.textContent = takenElsewhere ? `${label} (already used on this card)` : label
      })
    })
  }

  markDirty() {
    this.dirtyValue = true
    this.toggleFooter()
  }

  toggleFooter() {
    if (this.hasFooterTarget) this.footerTarget.classList.toggle("d-none", !this.dirtyValue)
  }
}
