// app/javascript/controllers/interim_save_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Finds the wizard form — controller is now on the outer wizard_container div.
  get form() {
    return this.element.querySelector("form.wizard_form")
  }

  interim(event) {
    event.preventDefault()
    const form = this.form

    // 1) Tag the submit as interim so server can skip validations
    let flag = form.querySelector('input[name="validate"]')
    if (!flag) {
      flag = document.createElement("input")
      flag.type = "hidden"
      flag.name = "validate"
      flag.value = "false"
      form.appendChild(flag)
    }

    // 2) **Null out** CSV config so its submit handler has nothing to do
    //    (also remove per-field data-validate to be extra safe)
    form.removeAttribute("data-client-side-validations")
    form.querySelectorAll("[data-validate]").forEach(el => el.removeAttribute("data-validate"))

    // 3) Submit the form directly, bypassing client-side validations and Turbo.
    form.submit()
  }

  // Standard submission — direct form.submit() to bypass Turbo/CSV blocks that
  // might be preventing submission on complex wizard forms (especially for admins).
  submit(event) {
    event.preventDefault()
    const form = this.form

    // Bypassing client-side validations and Turbo.
    form.removeAttribute("data-client-side-validations")
    form.querySelectorAll("[data-validate]").forEach(el => el.removeAttribute("data-validate"))

    form.submit()
  }

  // Final submission — opens a Bootstrap confirmation modal before submitting.
  final(event) {
    event.preventDefault()
    const modal = new bootstrap.Modal(document.getElementById("submitKycConfirmModal"))
    modal.show()
  }

  // Called by the modal's confirm button.
  confirmFinal(event) {
    bootstrap.Modal.getInstance(document.getElementById("submitKycConfirmModal"))?.hide()

    const form = this.form
    let actionField = form.querySelector('input[name="submit_action"]')
    if (!actionField) {
      actionField = document.createElement("input")
      actionField.type  = "hidden"
      actionField.name  = "submit_action"
      form.appendChild(actionField)
    }
    actionField.value = "final"
    form.submit()
  }
}
