import { Controller } from "@hotwired/stimulus"

// Gates the "Reset 2FA Method" submit button on the self-service reset modal
// (users/_reset_two_factor_modal): it stays disabled until the user has BOTH typed a
// password and ticked the "I understand my current method will stop working" box.
//
// The server re-checks the password regardless (TwoFactorReset#verify_password_if_self);
// this is purely so a stray click cannot fire the reset before the consequences were read.
// The admin variant of the modal has no password/acknowledge fields, so both targets are
// optional and the button is simply left enabled there.
export default class extends Controller {
  static targets = ["password", "acknowledge", "submit"]

  connect() {
    this.toggle()
  }

  toggle() {
    if (!this.hasSubmitTarget) return

    const passwordOk = !this.hasPasswordTarget || this.passwordTarget.value.trim().length > 0
    const acknowledged = !this.hasAcknowledgeTarget || this.acknowledgeTarget.checked

    this.submitTarget.disabled = !(passwordOk && acknowledged)
  }
}
