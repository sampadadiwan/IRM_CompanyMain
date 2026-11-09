import { Controller } from "@hotwired/stimulus"

// Gates the submit button of the two-factor confirmation popups:
//   * "Reset 2FA Method" (users/_reset_two_factor_modal) — self-service: password + acknowledgement;
//     the admin variant has neither field, so the button is simply left enabled there;
//   * "Turn off 2FA" (users/_disable_two_factor_modal) — password + current code + acknowledgement,
//     and a "Send code" button for WhatsApp / SMS users (OWASP 2026-11 M8).
// Every target is optional, so each popup uses only what it renders.
//
// The server re-checks everything regardless (TwoFactorReset / TwoFactorDisable); this is purely so a
// stray click cannot fire the action before the consequences were read.
export default class extends Controller {
  static targets = ["password", "acknowledge", "submit", "code", "status"]
  static values = { sendUrl: String }

  connect() {
    this.toggle()
  }

  toggle() {
    if (!this.hasSubmitTarget) return

    // Each input counts only when the popup renders it
    const passwordOk = !this.hasPasswordTarget || this.passwordTarget.value.trim().length > 0
    const codeOk = !this.hasCodeTarget || this.codeTarget.value.replace(/\s+/g, "").length >= 6
    const acknowledged = !this.hasAcknowledgeTarget || this.acknowledgeTarget.checked

    this.submitTarget.disabled = !(passwordOk && codeOk && acknowledged)
  }

  // "Send code" in the turn-off popup: asks the server to send the current code by WhatsApp / text
  // message and shows its answer in place (no page reload). The server holds the cooldown.
  async sendCode(event) {
    event.preventDefault()
    if (!this.hasSendUrlValue || !this.sendUrlValue) return

    const button = event.currentTarget
    button.disabled = true
    const token = document.querySelector('meta[name="csrf-token"]')?.content || ""

    try {
      const response = await fetch(this.sendUrlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": token, "Accept": "application/json" },
        credentials: "same-origin"
      })
      const body = await response.json().catch(() => ({}))
      // Success reads green, a refusal (cooldown, undeliverable) red
      this.showStatus(body.message || body.error || "Something went wrong. Please try again.", response.ok)
    } catch (_error) {
      this.showStatus("Something went wrong. Please try again.", false)
    } finally {
      button.disabled = false
    }
  }

  showStatus(message, ok) {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("text-success", ok)
    this.statusTarget.classList.toggle("text-danger", !ok)
  }
}
