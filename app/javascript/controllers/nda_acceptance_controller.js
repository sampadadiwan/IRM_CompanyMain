/**
 * @description Stimulus controller for the NDA acceptance screen.
 *   Enables/disables the Accept button based on the confirmation checkbox state.
 *   The Decline button is always enabled — only Accept requires explicit confirmation.
 */
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "acceptButton"]

  /**
   * @description Toggles the Accept button's disabled state based on checkbox.
   * @returns {void}
   */
  toggleAccept() {
    this.acceptButtonTarget.disabled = !this.checkboxTarget.checked
  }
}
