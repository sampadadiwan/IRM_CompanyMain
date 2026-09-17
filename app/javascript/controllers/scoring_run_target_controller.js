import { Controller } from "@hotwired/stimulus"

// Shows only the selector that matches the chosen "Run on" mode in the Portfolio
// Scoring Dashboard's run modal. All panels stay in the DOM so the form submits
// whichever one is visible; hidden panels contribute no selected options.
export default class extends Controller {
  static targets = ["selectedPanel", "sectorPanel", "tagPanel"]

  connect() {
    this.modeChanged({ target: this.element.querySelector('[name="target_mode"]') })
  }

  modeChanged(event) {
    const mode = event?.target?.value || "all"

    // Map each mode to the panel it reveals; "all" and "unscored" need no selector.
    const panels = {
      selected: this.hasSelectedPanelTarget ? this.selectedPanelTarget : null,
      by_sector: this.hasSectorPanelTarget ? this.sectorPanelTarget : null,
      by_tag: this.hasTagPanelTarget ? this.tagPanelTarget : null
    }

    Object.entries(panels).forEach(([key, panel]) => {
      if (!panel) return
      panel.classList.toggle("d-none", key !== mode)
      // Clear selections in hidden panels so a stale choice can't be submitted
      // after the FM switches modes.
      if (key !== mode) {
        panel.querySelectorAll("option:checked").forEach((option) => { option.selected = false })
      }
    })
  }
}
