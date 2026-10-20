import { Controller } from "@hotwired/stimulus"

// Opens the Start / Stop popup of the Support Console machine badge (support_console/_machine).
//
// The popup markup is rendered inside the badge's turbo-frame, which sits in .sc-header. That header
// is position: relative; z-index: 3, so a modal left inside it is stacked under Bootstrap's backdrop
// (appended to <body>) and nothing in it can be clicked. A copy is therefore shown from <body> and
// removed again when closed. Living on <body> also means a live badge update
// (SupportConsoleMachineControl.broadcast_status replaces the frame) cannot tear out an open popup.
//
// Usage (in the frame):
//   <button data-action="support-console-machine#open"
//           data-support-console-machine-modal-param="support-console-stop-modal">Stop</button>
//   <div class="modal fade" id="support-console-stop-modal">…</div>
export default class extends Controller {
  open(event) {
    // The popup rendered alongside the button, inside this frame
    const source = this.element.querySelector(`#${event.params.modal}`)
    if (!source) return

    // Only one copy at a time
    document.querySelectorAll("[data-support-console-machine-copy]").forEach((el) => el.remove())

    // Show a copy from <body>; the original stays hidden in the frame for the next click
    const modal = source.cloneNode(true)
    modal.setAttribute("data-support-console-machine-copy", "")
    document.body.appendChild(modal)
    modal.addEventListener("hidden.bs.modal", () => modal.remove(), { once: true })
    window.bootstrap?.Modal?.getOrCreateInstance(modal)?.show()
  }
}
