import { Controller } from "@hotwired/stimulus"

// Search-as-you-type for the documents panel: submits the form (into the documents frame)
// shortly after the user stops typing, so there is no button to find. Enter also works.
export default class extends Controller {
  static targets = ["input"]

  disconnect() {
    clearTimeout(this.timer)
  }

  // Wait for a pause in typing so each keystroke doesn't fire a request
  queue() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.element.requestSubmit(), 300)
  }

  // Empty the box and reload the panel's default list (LP: latest docs; fund: the root folder)
  clear() {
    clearTimeout(this.timer)
    this.inputTarget.value = ""
    this.element.requestSubmit()
    this.inputTarget.focus()
  }
}
