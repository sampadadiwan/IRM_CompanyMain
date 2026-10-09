import { Controller } from "@hotwired/stimulus"

// Polls the KYC processing endpoint (as JSON) until KycDocExtractorJob has finished, then
// navigates to the redirect URL it returns.
// Fallback for the Turbo Stream broadcast: when the job finishes before this page's stream
// subscription is open, the broadcast is lost and only this poll gets the page moving.
export default class extends Controller {
  static values = { url: String, interval: { type: Number, default: 3000 } }

  connect() {
    this.timer = setInterval(() => this.poll(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async poll() {
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      if (!response.ok) return

      // redirect_url is null while the job is still running
      const { redirect_url } = await response.json()
      if (redirect_url) {
        clearInterval(this.timer)
        Turbo.visit(redirect_url)
      }
    } catch (_e) {
      // Transient network error: keep polling on the next tick
    }
  }
}
