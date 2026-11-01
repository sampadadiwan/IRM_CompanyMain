import { Controller } from "@hotwired/stimulus"

// Export XLSX: shows "Preparing…" the moment it is clicked. The export job
// replaces the whole button with Download (or back to Export XLSX on failure)
// over the user's alert stream, so this never has to undo itself. Set here,
// not by the server's answer: a quick export can finish before that answer
// arrives and would otherwise be overwritten (report-builder-delivery H1, X1).
export default class extends Controller {
  prepare(event) {
    // A second click while preparing would start a second export
    if (this.element.dataset.preparing === "1") {
      event.preventDefault()
      return
    }
    this.element.dataset.preparing = "1"

    // Don't preventDefault: Turbo still sends the request that starts the job
    this.element.classList.add("disabled")
    this.element.setAttribute("aria-disabled", "true")
    this.element.innerHTML = `<span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span> Preparing…`
  }
}
