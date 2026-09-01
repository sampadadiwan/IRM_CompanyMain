import { Controller } from "@hotwired/stimulus"

// Enlarges one of the small authenticator-app QR codes into a shared modal.
//
// The trigger buttons and the modal are not DOM neighbours — the modal is rendered
// outside the layout's overflow:hidden wrapper (see devise.html.erb's `yield :modals`),
// while the buttons live deep inside the mode-selection/enrollment page. So this
// controller plays two independent roles on two different elements, coordinated
// through a window-dispatched event rather than Stimulus targets:
//   - the buttons wrapping each QR (data-controller="qr-zoom" on their common
//     ancestor) call #open, which reads the clicked QR's SVG and dispatches it
//   - the modal itself (its own data-controller="qr-zoom" instance) listens for
//     that dispatch via @window and populates itself in #populate
//
// Populating happens synchronously inside the same click, before the event bubbles
// to Bootstrap's own document-level data-bs-toggle listener — so the modal already
// holds the right code by the time Bootstrap shows it. No manual .show() needed.
export default class extends Controller {
  static targets = ["modalBody", "modalLabel"]

  open(event) {
    const svg = event.currentTarget.querySelector("svg")
    if (!svg) return

    this.dispatch("selected", {
      target: window,
      detail: { svg: svg.outerHTML, label: event.params.label },
    })
  }

  populate(event) {
    this.modalBodyTarget.innerHTML = event.detail.svg
    this.modalLabelTarget.textContent = event.detail.label
  }
}
