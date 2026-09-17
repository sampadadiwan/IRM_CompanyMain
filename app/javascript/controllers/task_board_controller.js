import { Controller } from "@hotwired/stimulus"

// Minimal HTML5 drag & drop for the tasks kanban board (tasks/_board.html.erb).
// Contract:
//   - controller wraps the whole board
//   - columns: data-task-board-target="column" + data-status (drop zones)
//   - cards:   data-task-board-target="card" + data-update-url
//              (PATCH /tasks/:id/update_status)
// No ordering within columns — a drop simply re-parents the card and persists
// the new status; the server responds with a turbo_stream replacing the card.
export default class extends Controller {
  static targets = ["column", "card"]

  dragStart(event) {
    this.dragged = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    // Firefox won't start a drag unless some data is set
    event.dataTransfer.setData("text/plain", this.dragged.id)
  }

  // Fires after every drag, including ESC-cancelled / off-board drops where
  // drop() never runs — without this a later unrelated drop (text, link, OS
  // file) would reuse the stale card reference and move the wrong task.
  dragEnd() {
    this.dragged = null
  }

  dragOver(event) {
    // Required to make the column a valid drop target
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  async drop(event) {
    event.preventDefault()
    const column = event.currentTarget
    const card = this.dragged
    this.dragged = null
    if (!card || card.parentElement === column) return

    // Optimistic move; reverted below if the server rejects the update
    const origin = card.parentElement
    column.appendChild(card)

    let response
    try {
      response = await fetch(card.dataset.updateUrl, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "text/vnd.turbo-stream.html",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
        },
        body: JSON.stringify({ status: column.dataset.status })
      })
    } catch {
      // Network-level failure (offline, server unreachable) — nothing was
      // saved, so the optimistic move must not stick
      origin.appendChild(card)
      return
    }

    if (!response.ok) {
      origin.appendChild(card)
      // The rejection reason travels in a header (URL-encoded server-side) so it
      // can be shown right where the drag happened, rather than only as a flash
      // at the top of the page where it is easy to miss.
      const encoded = response.headers.get("X-Task-Board-Error")
      this.showError(encoded ? decodeURIComponent(encoded) : "This task could not be moved.")
    }
    // Render the stream either way: success re-renders the card's badges,
    // failure carries the flash alert explaining the rejection (WithTurboFlash)
    const body = await response.text()
    if (body) window.Turbo.renderStreamMessage(body)
  }

  // Clicking a card loads its edit form into the board's "new_task" frame.
  // Bring it into view — the frame sits above the columns, so on a long board
  // the form would otherwise open off-screen and the click look like a no-op.
  //
  // Bound to turbo:frame-render as well as turbo:frame-load: frame-load only
  // fires the first time the frame loads, so opening a second card (into a frame
  // that already holds a form) renders without ever firing it. Delegated from the
  // board root so it keeps working after update.turbo_stream swaps the frame
  // element itself for a blank one.
  scrollToForm(event) {
    const frame = event.target
    if (!frame || frame.id !== "new_task") return
    // Also fires when the form is cleared after a save; nothing to scroll to then
    if (!frame.innerHTML.trim()) return
    // Next frame, so the form is laid out before we measure where to scroll
    requestAnimationFrame(() => frame.scrollIntoView({ behavior: "smooth", block: "start" }))
  }

  // Bootstrap toast, bottom-right, dismissible and auto-hiding. Built here
  // rather than server-rendered so it survives the card's turbo_stream replace.
  showError(message) {
    const el = document.createElement("div")
    el.className = "toast align-items-center text-bg-danger border-0 position-fixed"
    el.style.cssText = "bottom:1rem;right:1rem;z-index:9999;min-width:260px"
    el.setAttribute("role", "alert")
    el.setAttribute("aria-live", "assertive")
    el.innerHTML = `
      <div class="d-flex">
        <div class="toast-body fw-semibold"></div>
        <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast" aria-label="Close"></button>
      </div>`
    // textContent, not innerHTML — the message is server text and must not be
    // interpreted as markup
    el.querySelector(".toast-body").textContent = message
    document.body.appendChild(el)
    const toast = new bootstrap.Toast(el, { delay: 6000 })
    toast.show()
    el.addEventListener("hidden.bs.toast", () => el.remove())
  }
}
