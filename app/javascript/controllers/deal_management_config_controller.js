import { Controller } from "@hotwired/stimulus"

/**
 * Stimulus controller for the DealManagementAgent custom config partial.
 * Manages the deal selector dropdown and step transition checkboxes,
 * syncing selections into the hidden json_fields input for form submission.
 *
 * @see _deal_management_config.html.erb
 * @see _deal_steps_frame.html.erb
 */
export default class extends Controller {
  static targets = ["jsonField", "dealSelect", "checkbox", "count"]
  static values = { stepsUrl: String }

  /**
   * Handles deal selection change — updates json_fields with the new deal_id,
   * clears preset_steps, and reloads the step transitions Turbo Frame.
   */
  dealChanged() {
    const dealId = this.dealSelectTarget.value
    this.#updateJson({ deal_ids: dealId, preset_steps: "" })

    // Fetch updated steps via Turbo Frame
    const url = `${this.stepsUrlValue}?deal_id=${dealId}`
    const frame = document.getElementById("deal-steps-frame")
    if (frame) {
      frame.src = url
      frame.reload()
    }
  }

  /**
   * Handles step transition checkbox changes — collects all checked values
   * into a CSV string and updates json_fields.preset_steps.
   */
  updateSteps() {
    const checked = this.checkboxTargets
      .filter(cb => cb.checked)
      .map(cb => cb.value)

    this.#updateJson({ preset_steps: checked.join(",") })

    if (this.hasCountTarget) {
      this.countTarget.textContent = checked.length > 0 ? checked.length : "All"
    }
  }

  /**
   * Merges key/value updates into the hidden json_fields input.
   * @param {Object} updates - key/value pairs to merge into existing JSON
   * @private
   */
  #updateJson(updates) {
    const data = JSON.parse(this.jsonFieldTarget.value || "{}")
    Object.assign(data, updates)
    this.jsonFieldTarget.value = JSON.stringify(data)
  }
}
