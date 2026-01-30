import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="toggle-display"
export default class extends Controller {
  static values = {
    value: String,         // The value that triggers the display (e.g. "compute")
    selector: String       // The selector of the element(s) to show/hide
  }

  connect() {
    this.toggle()
  }

  toggle(event) {
    // If triggered by event, use event.target, otherwise look for input/select in this element
    let input = this.element

    // If the controller is on a wrapper (div), find the input inside
    if (this.element.tagName !== "INPUT" && this.element.tagName !== "SELECT") {
        input = this.element.querySelector('select, input')
    }

    // If event is provided, trust the event target
    if (event && event.target) {
        input = event.target
    }

    if (!input) return

    const currentValue = input.value
    const targets = document.querySelectorAll(this.selectorValue)

    targets.forEach(el => {
      if (currentValue === this.valueValue) {
        el.hidden = false
        el.style.display = ""
        el.classList.remove("d-none")
      } else {
        el.hidden = true
        el.style.display = "none"
        el.classList.add("d-none")
      }
    })
  }
}
