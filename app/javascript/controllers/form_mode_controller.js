import { Controller } from "@hotwired/stimulus"

// Toggles a wizard form between a guided step-by-step mode and a single "classic"
// page showing every field at once. Both modes share the exact same <form>/inputs
// (CSS just shows/hides the .setup-content step cards), so nothing entered is lost
// when switching and there is no duplicate-field risk. Generic — shared by every
// wizard that offers a Classic Form toggle (Custom Notification, Capital Call, ...);
// don't fork this per-wizard, see docs/technical/wizard_form_patterns.md.
export default class extends Controller {
  static targets = ["wizardModeBtn", "classicModeBtn"]

  connect() {
    this.submitBtn = $(this.element).find(".wizard_form").find("input[type='submit'], button[type='submit']")
    this.showWizard()
  }

  showWizard() {
    this.element.classList.remove("mode-classic")

    // Re-run the wizard controller's own setup so the per-step Next/Back click
    // handlers and the "only validate the current step" submit intercept are
    // restored (it was left in place before, .off/.on inside makes this safe to redo).
    const wizardController = this.application.getControllerForElementAndIdentifier(this.element, "wizard")
    if (wizardController) wizardController.initialize()

    this.wizardModeBtnTarget.classList.add("active")
    this.classicModeBtnTarget.classList.remove("active")
  }

  showClassic() {
    this.element.classList.add("mode-classic")

    // Classic mode submits the whole form at once, like the form did before the
    // wizard existed — drop the wizard's "current step only" submit intercept and
    // let the plain submit (and the form's own client-side validations) run instead.
    this.submitBtn.off("click")

    this.classicModeBtnTarget.classList.add("active")
    this.wizardModeBtnTarget.classList.remove("active")
  }
}
