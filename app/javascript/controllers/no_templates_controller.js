import { Controller } from "@hotwired/stimulus"

// Hides the "Clone From" group when "No Templates" is checked.
export default class extends Controller {
  static targets = ["checkbox", "cloneGroup"]

  connect() {
    this.toggle()
  }

  toggle() {
    const hide = this.checkboxTarget.checked
    this.cloneGroupTargets.forEach(el => {
      el.style.display = hide ? "none" : ""
    })
  }
}
