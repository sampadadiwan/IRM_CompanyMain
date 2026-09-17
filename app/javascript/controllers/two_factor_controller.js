import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
  }

  sendWhatsapp(event) {
    this.#requestCode(event, "/two_factor/send_whatsapp", "whatsapp-status")
  }

  // SMS resend. Shares the request/feedback path with WhatsApp because the two behave
  // identically from the browser's point of view — a POST that either enqueues a send
  // or refuses. The difference is on the server, where an SMS send costs money and so
  // passes durable rate limits the WhatsApp path does not have.
  sendSms(event) {
    this.#requestCode(event, "/two_factor/send_sms", "sms-status")
  }

  // Shared so a fix to the error handling applies to both channels rather than to
  // whichever copy someone happened to edit.
  #requestCode(event, url, statusElementId) {
    event.preventDefault()
    const btn = event.currentTarget
    const status = document.getElementById(statusElementId)

    // Disabled for the duration of the request: without it a double-click sends two
    // codes. On the SMS path that is two charges, and the second code invalidates the
    // first in the user's mind while both remain valid within the TOTP window.
    btn.disabled = true
    status.style.display = "block"
    status.textContent = "Sending code..."
    status.className = "text-center mt-2 text-info"

    fetch(url, {
      method: "POST",
      headers: {
        "X-CSRF-Token": this.csrfToken,
        "Content-Type": "application/json"
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data.error) {
        // The server deliberately returns one generic refusal for every rate-limit
        // scope — which limit tripped, and when it resets, would let someone probe
        // the thresholds. Whatever it says is what the user sees.
        status.textContent = data.error
        status.className = "text-center mt-2 text-danger"
      } else {
        status.textContent = data.message
        status.className = "text-center mt-2 text-success"
      }
    })
    .catch(() => {
      status.textContent = "Failed to send code. Please try again."
      status.className = "text-center mt-2 text-danger"
    })
    .finally(() => {
      btn.disabled = false
    })
  }
}
