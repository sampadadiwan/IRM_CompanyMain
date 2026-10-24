import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="report-parts"
//
// The list of report rows on the legacy bulk generate options page. The order of the rows is the
// order of the parts in the final document. Each row is its own report-template-filter scope.
//
// Rows are checked here, before anything is sent: every row needs a template (X1), a template may
// appear in only one row (X2), and "Generate Extracts Only" needs at least one report that is not
// consolidated (X5). A row's message clears as soon as that row changes (E17). The server repeats the
// same checks for a request that bypasses the page.
export default class extends Controller {
  static targets = ["rows", "blueprint", "row", "remove", "message", "extractsMessage"]
  static values = {
    templateMissingMessage: String,
    templateRepeatedMessage: String,
    extractsOnlyMessage: String
  }

  connect() {
    this.nextIndex = this.rowTargets.length
    this.refreshRemoveButtons()
  }

  // Add report: clone the blueprint with a fresh row number
  add() {
    const html = this.blueprintTarget.innerHTML.replaceAll("__INDEX__", this.nextIndex)
    this.nextIndex += 1
    this.rowsTarget.insertAdjacentHTML("beforeend", html)
    this.refreshRemoveButtons()
  }

  // Remove the row the button belongs to; the last remaining row cannot be removed
  remove(event) {
    if (this.rowTargets.length <= 1) return

    event.target.closest("[data-report-parts-target='row']").remove()
    this.refreshRemoveButtons()
  }

  // Hide every Remove button while only one row is left
  refreshRemoveButtons() {
    const onlyOne = this.rowTargets.length <= 1
    this.removeTargets.forEach(button => button.classList.toggle("d-none", onlyOne))
  }

  // E17: a changed row loses its message at once; the next submit checks it again
  rowChanged(event) {
    this.clearRow(event.target.closest("[data-report-parts-target='row']"))
  }

  validate(event) {
    const mode = event.submitter?.value
    if (mode === "full_report") {
      if (!this.rowsAreValid()) event.preventDefault()
    } else if (mode === "extracts_only") {
      if (!this.hasNormalReport()) {
        event.preventDefault()
        this.extractsMessageTarget.textContent = this.extractsOnlyMessageValue
        this.extractsMessageTarget.classList.add("d-block")
      }
    }
  }

  // X1, X2: marks every row that has no template, or whose template an earlier row already uses
  rowsAreValid() {
    let valid = true
    const seen = new Set()
    this.rowTargets.forEach(row => {
      this.clearRow(row)
      const templateId = row.querySelector("[data-report-template-filter-target='template']").value
      if (!templateId) {
        this.showRowMessage(row, this.templateMissingMessageValue)
        valid = false
      } else if (seen.has(templateId)) {
        this.showRowMessage(row, this.templateRepeatedMessageValue)
        valid = false
      } else {
        seen.add(templateId)
      }
    })
    return valid
  }

  // X5: true when at least one row's selected report is not consolidated
  hasNormalReport() {
    return this.rowTargets.some(row => {
      const report = row.querySelector("[data-report-template-filter-target='report']")
      return report.selectedOptions[0]?.dataset.consolidated === "false"
    })
  }

  showRowMessage(row, text) {
    const message = row.querySelector("[data-report-parts-target='message']")
    message.textContent = text
    message.classList.add("d-block")
    row.querySelector("[data-report-template-filter-target='template']").classList.add("is-invalid")
  }

  clearRow(row) {
    const message = row.querySelector("[data-report-parts-target='message']")
    message.textContent = ""
    message.classList.remove("d-block")
    row.querySelector("[data-report-template-filter-target='template']").classList.remove("is-invalid")
    if (this.hasExtractsMessageTarget) {
      this.extractsMessageTarget.textContent = ""
      this.extractsMessageTarget.classList.remove("d-block")
    }
  }
}
