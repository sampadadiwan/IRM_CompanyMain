import { Controller } from "@hotwired/stimulus"

// Shows the "Go to step #" field only when on_reject_rule is set to "go_to_step_n".
export default class extends Controller {
  static targets = ["goToStepField"]

  connect() {
    this.toggle(this.element.querySelector("select")?.value)
  }

  toggleGoToStep(event) {
    this.toggle(event.target.value)
  }

  toggle(value) {
    this.goToStepFieldTarget.classList.toggle("d-none", value !== "go_to_step_n")
  }
}
