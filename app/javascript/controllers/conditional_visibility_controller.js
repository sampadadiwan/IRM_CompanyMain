import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="conditional-visibility"
export default class extends Controller {
  static targets = ["conditional", "source"]

  connect() {
    this.toggle()
  }

  toggle() {
    const source = this.sourceTarget
    // Checkboxes/radios gate on checked state; anything else (e.g. a text field like
    // attachment_names) gates on having a non-blank value.
    const isActive = (source.type === "checkbox" || source.type === "radio")
      ? source.checked
      : source.value.trim().length > 0

    if (isActive) {
      this.show()
    } else {
      this.hide()
    }
  }

  show() {
    this.conditionalTargets.forEach(target => {
      target.hidden = false
      target.disabled = false
    })
  }

  hide() {
    this.conditionalTargets.forEach(target => {
      target.hidden = true
      target.disabled = true
    })
  }
}
