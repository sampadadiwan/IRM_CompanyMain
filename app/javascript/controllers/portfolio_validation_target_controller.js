// Manages the Run Validation target selector — shows/hides the appropriate
// secondary selector panel (companies, tags, or sectors) based on target_mode.
// Also validates that at least one item is checked and shows a dynamic
// confirmation dialog before form submission.
//
// @see _actions.html.erb for the form markup
// @see PortfolioCompanyDashboardController#run_validation for server-side handling
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["selectedPanel", "tagPanel", "sectorPanel"]
  static values = { totalCount: Number }

  connect() {
    this.updatePanels()
  }

  // Called when the target_mode dropdown changes.
  // Hides all panels, then reveals only the one matching the selected mode.
  modeChanged() {
    this.updatePanels()
  }

  // Shows the panel matching the current target_mode, hides the others.
  updatePanels() {
    const mode = this.element.querySelector("[name='target_mode']")?.value || "all"

    if (this.hasSelectedPanelTarget) this.selectedPanelTarget.hidden = mode !== "selected"
    if (this.hasTagPanelTarget) this.tagPanelTarget.hidden = mode !== "by_tag"
    if (this.hasSectorPanelTarget) this.sectorPanelTarget.hidden = mode !== "by_sector"
  }

  // Builds a human-readable label describing the current target selection.
  // Used in the confirmation dialog so the FM knows exactly what will run.
  targetLabel() {
    const mode = this.element.querySelector("[name='target_mode']")?.value || "all"

    if (mode === "selected" && this.hasSelectedPanelTarget) {
      const count = this.selectedPanelTarget.querySelectorAll("input[type='checkbox']:checked").length
      return `${count} selected ${count === 1 ? "company" : "companies"}`
    } else if (mode === "by_tag" && this.hasTagPanelTarget) {
      const checked = this.tagPanelTarget.querySelectorAll("input[type='checkbox']:checked")
      const names = Array.from(checked).map(el => el.value).join(", ")
      return `companies tagged ${names}`
    } else if (mode === "by_sector" && this.hasSectorPanelTarget) {
      const checked = this.sectorPanelTarget.querySelectorAll("input[type='checkbox']:checked")
      const names = Array.from(checked).map(el => el.value).join(", ")
      return `companies in ${names}`
    }

    return `all ${this.totalCountValue} portfolio companies`
  }

  // Validates that at least one checkbox is checked for non-"all" modes,
  // then shows a dynamic confirmation dialog before allowing form submission.
  validateAndSubmit(event) {
    const mode = this.element.querySelector("[name='target_mode']")?.value || "all"

    if (mode === "selected" && this.hasSelectedPanelTarget) {
      const checked = this.selectedPanelTarget.querySelectorAll("input[type='checkbox']:checked")
      if (checked.length === 0) {
        event.preventDefault()
        alert("Please select at least one company.")
        return
      }
    } else if (mode === "by_tag" && this.hasTagPanelTarget) {
      const checked = this.tagPanelTarget.querySelectorAll("input[type='checkbox']:checked")
      if (checked.length === 0) {
        event.preventDefault()
        alert("Please select at least one tag.")
        return
      }
    } else if (mode === "by_sector" && this.hasSectorPanelTarget) {
      const checked = this.sectorPanelTarget.querySelectorAll("input[type='checkbox']:checked")
      if (checked.length === 0) {
        event.preventDefault()
        alert("Please select at least one sector.")
        return
      }
    }

    if (!confirm(`Run validation on ${this.targetLabel()}?`)) {
      event.preventDefault()
    }
  }
}
