import { Controller } from "@hotwired/stimulus"

// Remembers whether a Bootstrap collapse is open or shut, for this user, on the server.
//
// The element is the `.collapse` itself; Bootstrap's own toggle button (data-bs-toggle="collapse")
// opens and shuts it, so this controller only listens for the result and saves it. The page renders
// the saved state on the next visit (no flicker, and it follows the user to another browser).
// Used by the Compliance Getting started journey (E202) — its minimise toggle.
//
// Usage:
//   <div class="collapse show" id="x" data-controller="collapse-preference"
//        data-collapse-preference-url-value="/compliance/getting_started/collapse">
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.saveShown = () => this.save(false)
    this.saveHidden = () => this.save(true)
    this.element.addEventListener("shown.bs.collapse", this.saveShown)
    this.element.addEventListener("hidden.bs.collapse", this.saveHidden)
  }

  disconnect() {
    this.element.removeEventListener("shown.bs.collapse", this.saveShown)
    this.element.removeEventListener("hidden.bs.collapse", this.saveHidden)
  }

  // Fire and forget: a failed save only means the panel opens expanded next time
  save(collapsed) {
    if (!this.hasUrlValue) return

    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "text/plain"
      },
      body: new URLSearchParams({ collapsed: String(collapsed) })
    })
  }
}
