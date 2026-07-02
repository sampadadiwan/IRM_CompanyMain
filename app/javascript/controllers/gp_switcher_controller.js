import { Controller } from "@hotwired/stimulus"

// Handles the GP entity picker in the LP dashboard topbar.
//
// The controller element is rendered as a hidden div (so it can use Rails
// helpers) and then moved into #topbar_gp_dropdown on connect. Moving the
// element rather than cloning its innerHTML keeps Stimulus bindings intact.
//
// On change, redirects to the GP's branded subdomain when one is configured,
// or falls back to a turbo frame update for entities without a subdomain.
export default class extends Controller {
  static targets = ["select"]
  static values  = { subdomains: Object, baseDomain: String, protocol: String }

  connect() {
    const target = document.getElementById("topbar_gp_dropdown")
    // Guard: skip if already inside the topbar (Stimulus re-fires connect
    // after appendChild moves the element in the DOM).
    if (target && this.element.parentElement !== target) {
      this.element.classList.remove("d-none")
      target.appendChild(this.element)
    }
  }

  // Wired via data-action="change->gp-switcher#switch" on the <select>
  switch(event) {
    const subdomain = this.subdomainsValue[event.target.value]

    if (subdomain) {
      window.location = `${this.protocolValue}${subdomain}.${this.baseDomainValue}/`
    } else {
      event.target.closest("form").requestSubmit()
    }
  }
}
