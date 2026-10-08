import { Controller } from "@hotwired/stimulus"

// Step editor: shows the fields that apply to the chosen step kind.
// Human steps use approvers, quorum and reject rules; system and acknowledge steps use a check,
// a skip rule and an owner instead. Actors show for human steps and for the few system checks that
// email someone (WorkflowStep::ACTOR_CHECK_KEYS, listed in the actors block's data-actor-check-keys).
export default class extends Controller {
  static targets = ["humanFields", "checkFields", "checkSelect", "actorFields"]

  connect() {
    this.toggle(this.currentKind())
  }

  change(event) {
    this.toggle(event.target.value)
  }

  // The check changed: re-decide whether the actors block applies
  refresh() {
    this.toggle(this.currentKind())
  }

  currentKind() {
    // The checked radio button holds the kind; default to human for new steps
    return this.element.querySelector("input[name$='[kind]']:checked")?.value || "human"
  }

  toggle(kind) {
    const human = kind === "human"
    this.humanFieldsTargets.forEach((el) => el.classList.toggle("d-none", !human))
    this.checkFieldsTargets.forEach((el) => el.classList.toggle("d-none", human))
    this.actorFieldsTargets.forEach((el) => {
      const keys = JSON.parse(el.dataset.actorCheckKeys || "[]")
      const check = this.hasCheckSelectTarget ? this.checkSelectTarget.value : ""
      el.classList.toggle("d-none", !(human || keys.includes(check)))
    })
  }
}
