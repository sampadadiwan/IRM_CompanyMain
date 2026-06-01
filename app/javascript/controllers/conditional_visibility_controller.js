import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="conditional-visibility"
export default class extends Controller {
  static targets = ["conditional", "source"]

  connect() {
    this.toggle()
  }

  toggle() {
    if (this.sourceTarget.checked) {
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
