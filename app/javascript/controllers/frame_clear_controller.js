import { Controller } from "@hotwired/stimulus"

// Empties a turbo-frame in place, no server round-trip. Used by "Cancel" buttons
// on forms that were loaded into an otherwise-blank frame, so cancelling puts the
// frame back the way the index rendered it.
export default class extends Controller {
  static values = { frame: String }

  clear(event) {
    event.preventDefault()

    // Falls back to the frame the button sits in, so the value is optional.
    const frame = this.hasFrameValue
      ? document.getElementById(this.frameValue)
      : this.element.closest("turbo-frame")

    if (frame) frame.innerHTML = ""
  }
}
