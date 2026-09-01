import { Controller } from "@hotwired/stimulus"

// Toggle between display and edit mode for inline editing.
// Targets: display (read-only view), editor (edit form), input (auto-focus).
export default class extends Controller {
  static targets = ["display", "editor", "input"]

  show() {
    this.displayTarget.classList.add("d-none")
    this.editorTarget.classList.remove("d-none")
    if (this.hasInputTarget) this.inputTarget.focus()
  }

  hide() {
    this.editorTarget.classList.add("d-none")
    this.displayTarget.classList.remove("d-none")
  }
}
