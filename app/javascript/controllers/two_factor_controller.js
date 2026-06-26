import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
  }

  sendWhatsapp(event) {
    event.preventDefault()
    const btn = event.currentTarget
    const status = document.getElementById("whatsapp-status")

    btn.disabled = true
    status.style.display = "block"
    status.textContent = "Sending code..."
    status.className = "text-center mt-2 text-info"

    fetch("/two_factor/send_whatsapp", {
      method: "POST",
      headers: {
        "X-CSRF-Token": this.csrfToken,
        "Content-Type": "application/json"
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data.error) {
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
