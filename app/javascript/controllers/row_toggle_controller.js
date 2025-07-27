import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["control"]

  connect() {
    // hide all child rows on initialize
    this.element.querySelectorAll("tbody tr.child").forEach(ch => {
      ch.style.display = "none"
    })
    // reset only the symbol spans inside control targets
    this.controlTargets.forEach(ctrl => {
      const span = ctrl.querySelector("span.expand")
      if (span) span.textContent = "+"
    })
  }

  toggle(event) {
    const control = event.currentTarget
    const symbol = control.querySelector("span.expand")
    const opening = symbol && symbol.textContent === "+"
    const parentRow = control.closest("tr")
    let next = parentRow.nextElementSibling

    while (next && !next.classList.contains("parent")) {
      if (next.classList.contains("child")) {
        next.style.display = opening ? "" : "none"
      }
      next = next.nextElementSibling
    }

    if (symbol) symbol.textContent = opening ? "−" : "+"
  }
}
