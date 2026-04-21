import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["url"]

  change(event) {
    const button = event.target.closest(".btn")
    if (!button) return

    const period = button.dataset.period
    const url = new URL(this.urlTarget.value, window.location.origin)
    url.searchParams.set("chart_period", period)

    // Update active state
    this.element.querySelectorAll(".btn").forEach(btn => {
      btn.classList.remove("btn-primary", "rounded-2", "shadow-sm", "active")
      btn.classList.add("btn-link", "text-muted", "text-decoration-none")
    })

    button.classList.remove("btn-link", "text-muted", "text-decoration-none")
    button.classList.add("btn-primary", "rounded-2", "shadow-sm", "active")

    fetch(url, {
      headers: {
        Accept: "text/vnd.turbo-stream.html"
      }
    })
    .then(r => r.text())
    .then(html => {
      Turbo.renderStreamMessage(html)
    })
  }
}
