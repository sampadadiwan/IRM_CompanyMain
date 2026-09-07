import { Controller } from "@hotwired/stimulus"

// Reloads the enclosing Turbo Frame every `interval` ms while `active` is true.
//
// Used by the allocation group run progress panel. The controller sits on a div *inside*
// the frame (not on the frame itself): Turbo replaces the frame's children on each reload,
// so a fresh controller instance connects with the server's latest `active` value and the
// polling stops by itself once the run has finished.
//
//   <turbo-frame id="group_run_progress">
//     <div data-controller="auto-refresh"
//          data-auto-refresh-url-value="/allocation_group_runs/1"
//          data-auto-refresh-active-value="true"
//          data-auto-refresh-interval-value="5000">…</div>
//   </turbo-frame>
export default class extends Controller {
  static values = {
    url: String,
    active: Boolean,
    interval: { type: Number, default: 5000 }
  }

  connect() {
    this.schedule()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  schedule() {
    clearTimeout(this.timer)
    if (!this.activeValue) return
    this.timer = setTimeout(() => this.refresh(), this.intervalValue)
  }

  refresh() {
    const frame = this.element.closest("turbo-frame")
    if (!frame) return
    // The first refresh sets src (which makes Turbo fetch it); later ones reload the frame.
    if (frame.src) {
      frame.reload()
    } else {
      frame.src = this.urlValue
    }
  }
}
