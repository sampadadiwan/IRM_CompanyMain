// app/javascript/controllers/interim_save_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Going Back restores this page from the bfcache with the buttons still locked - unlock them
    this.unlock = (event) => { if (event.persisted) this.#unlockForm() }
    window.addEventListener("pageshow", this.unlock)
  }

  disconnect() {
    window.removeEventListener("pageshow", this.unlock)
  }

  // Finds the wizard form — controller is now on the outer wizard_container div.
  get form() {
    return this.element.querySelector("form.wizard_form")
  }

  interim(event) {
    event.preventDefault()
    // A second click while the first submit is in flight would save the form (and its files) again
    if (!this.#lockForm(event.currentTarget)) return
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
    if (!this.#lockForm(event.currentTarget)) return
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
    if (!this.#lockForm(event.currentTarget)) return
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

  // form.submit() skips Turbo/UJS, so nothing disables the buttons for us. Disable every button in the
  // wizard (Save, Save Draft, Submit, the modal's confirm) and show "Saving..." on the one clicked.
  // Returns false when a submit is already under way, so the caller does nothing.
  #lockForm(clicked) {
    if (this.submitting) return false
    this.submitting = true

    // Remember each button's own disabled state so an unlock restores it exactly
    this.element.querySelectorAll("button, input[type=submit]").forEach(btn => {
      btn.dataset.interimSaveWasDisabled = btn.disabled
      btn.disabled = true
    })
    // Keep the clicked button's label so a bfcache restore can put it back
    if (clicked) {
      clicked.dataset.interimSaveLabel = clicked.innerHTML
      clicked.innerHTML = '<span class="spinner-border spinner-border-sm me-1" role="status" aria-hidden="true"></span>Saving...'
    }
    return true
  }

  // Undo #lockForm: restore each button's own disabled state and the clicked button's label
  #unlockForm() {
    this.submitting = false
    this.element.querySelectorAll("[data-interim-save-was-disabled]").forEach(btn => {
      btn.disabled = btn.dataset.interimSaveWasDisabled === "true"
      delete btn.dataset.interimSaveWasDisabled
    })
    this.element.querySelectorAll("[data-interim-save-label]").forEach(btn => {
      btn.innerHTML = btn.dataset.interimSaveLabel
      delete btn.dataset.interimSaveLabel
    })
  }
}
