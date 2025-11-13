// app/javascript/controllers/interim_save_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  interim(event) {
    event.preventDefault()
    const form = this.element

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
}
