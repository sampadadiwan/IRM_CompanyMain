import { Controller } from "@hotwired/stimulus"

// Step editor: shows the fields that apply to the chosen step kind.
// Human steps use approvers, quorum and reject rules; system and acknowledge steps use a check,
// a skip rule and an owner instead.
export default class extends Controller {
  static targets = ["humanFields", "checkFields", "checkSelect"]

  connect() {
    this.toggle(this.currentKind())
  }

  change(event) {
    this.toggle(event.target.value)
  }

  currentKind() {
    // The checked radio button holds the kind; default to human for new steps
    return this.element.querySelector("input[name$='[kind]']:checked")?.value || "human"
  }

  toggle(kind) {
    const human = kind === "human"
    this.humanFieldsTargets.forEach((el) => el.classList.toggle("d-none", !human))
    this.checkFieldsTargets.forEach((el) => el.classList.toggle("d-none", human))
  }
}
