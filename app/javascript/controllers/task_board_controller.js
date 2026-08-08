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

    if (!response.ok) origin.appendChild(card)
    // Render the stream either way: success re-renders the card's badges,
    // failure carries the flash alert explaining the rejection (WithTurboFlash)
    const body = await response.text()
    if (body) window.Turbo.renderStreamMessage(body)
  }
}
