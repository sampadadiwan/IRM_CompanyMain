import { Controller } from "@hotwired/stimulus"

// Document form: the tag chips under the Tags box ("Used in this folder") add their tag to the
// comma-separated text field. The field stays a plain text input, so typing (and Capybara's
// fill_in) works as before; the chips are only a shortcut.
// A chip is only shown while its tag is NOT in the box: adding one hides it, deleting that tag from
// the box brings it back, and the whole line hides when nothing is left to suggest.
export default class extends Controller {
  static targets = ["input", "chip", "list"]

  connect() {
    this.sync()
  }

  // Tags currently in the box, trimmed, lower-cased, without blanks
  current() {
    return this.inputTarget.value.split(",").map((t) => t.trim()).filter(Boolean)
  }

  add(event) {
    event.preventDefault()
    const tag = event.currentTarget.dataset.tag
    const tags = this.current()

    // Add it once - case-insensitive, so "IC Note" and "ic note" don't both go in
    if (!tags.some((t) => t.toLowerCase() === tag.toLowerCase())) tags.push(tag)
    this.inputTarget.value = tags.join(", ")

    // Let client-side validation and anything else listening see the change
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.sync()
  }

  // Show only the chips whose tag is not in the box yet (runs on load and as the box is edited)
  sync() {
    if (!this.hasListTarget) return
    const inBox = this.current().map((t) => t.toLowerCase())
    let shown = 0
    this.chipTargets.forEach((chip) => {
      const hide = inBox.includes(chip.dataset.tag.toLowerCase())
      chip.classList.toggle("d-none", hide)
      if (!hide) shown += 1
    })
    this.listTarget.classList.toggle("d-none", shown === 0)
  }
}
