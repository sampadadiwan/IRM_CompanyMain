import { Controller } from "@hotwired/stimulus"

// Closes the parent Bootstrap modal when a Turbo form submission succeeds.
//
// Usage:
//   <%= form_with ..., data: { controller: "modal-form", action: "turbo:submit-end->modal-form#close" } %>
//
// The controller walks up the DOM to find the closest .modal element and hides
// it via the Bootstrap Modal API. It only closes on a successful response
// (event.detail.success === true).
export default class extends Controller {
  close(event) {
    if (!event.detail.success) return

    const modalEl = this.element.closest(".modal")
    if (!modalEl) return

    const modal = bootstrap.Modal.getInstance(modalEl)
    modal?.hide()
  }
}
