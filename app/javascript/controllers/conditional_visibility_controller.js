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

    // A target may instead list the source values it shows for (data-show-when="a b"), e.g. the
    // LP portfolio view's formula pickers (lp-folio-portfolio-dashboard E8)
    this.conditionalTargets.forEach(target => {
      const showWhen = target.dataset.showWhen
      const visible = showWhen ? showWhen.split(/\s+/).includes(source.value) : isActive
      this.setVisible(target, visible)
    })
  }

  show() {
    this.conditionalTargets.forEach(target => this.setVisible(target, true))
  }

  hide() {
    this.conditionalTargets.forEach(target => this.setVisible(target, false))
  }

  // Hidden targets are also disabled so their fields are not submitted
  setVisible(target, visible) {
    target.hidden = !visible
    target.disabled = !visible
  }
}
