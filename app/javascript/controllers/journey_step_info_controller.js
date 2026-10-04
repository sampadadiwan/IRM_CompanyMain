import { Controller } from "@hotwired/stimulus"

// Opens a journey step's popup when its pill in the step rail is clicked.
//
// The record's page carries no popup markup: each pill only has its URL
// (data-journey-step-info-url-param). On click the popup is fetched from
// WorkflowInstancesController#step_info, appended to <body> and shown; it is removed again when
// closed. So the show page stays small, and the popup always reflects the step's latest result.
//
// It lives on <body>, not inside the journey turbo-frame, because live updates replace that frame —
// an open modal inside it would be torn out and leave its backdrop behind.
//
// Usage (on the rail):
//   <div data-controller="journey-step-info">
//     <span data-action="click->journey-step-info#open keydown.enter->journey-step-info#open"
//           data-journey-step-info-url-param="/workflow_instances/1/step_info?position=3">…</span>
export default class extends Controller {
  async open(event) {
    const url = event.params.url
    if (!url || this.loading) return

    // The pill's hover tooltip would otherwise sit on top of the popup
    window.bootstrap?.Tooltip?.getInstance(event.currentTarget)?.hide()

    this.loading = true
    try {
      const response = await fetch(url, { headers: { Accept: "text/html" } })
      if (!response.ok) return

      this.show(await response.text())
    } finally {
      this.loading = false
    }
  }

  // Close the popup when one of its action buttons is used; the button's own link/form still runs
  dismiss(event) {
    const modal = event.target.closest(".modal")
    if (modal && event.target.closest("a, button")) window.bootstrap?.Modal?.getInstance(modal)?.hide()
  }

  show(html) {
    // Only one popup at a time
    document.getElementById("journeyStepInfoModal")?.remove()

    const holder = document.createElement("div")
    holder.innerHTML = html.trim()
    const modal = holder.firstElementChild
    if (!modal) return

    // Its buttons call back into this controller (dismiss), so the popup is its own controller scope
    modal.setAttribute("data-controller", "journey-step-info")
    document.body.appendChild(modal)
    modal.addEventListener("hidden.bs.modal", () => modal.remove(), { once: true })
    window.bootstrap?.Modal?.getOrCreateInstance(modal)?.show()
  }
}
