/**
 * Copy-to-clipboard Stimulus controller.
 * Copies the text from a target element and shows a brief "Copied!" feedback.
 * Falls back to execCommand for non-HTTPS contexts (e.g. local dev on HTTP).
 *
 * Usage:
 *   <div data-controller="clipboard">
 *     <span data-clipboard-target="source">text to copy</span>
 *     <button data-action="click->clipboard#copy">Copy</button>
 *   </div>
 */
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source"]

  /** Copy the source target's text to the system clipboard. */
  copy(event) {
    const text = this.sourceTarget.textContent.trim()
    const button = event.currentTarget

    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(() => this.showFeedback(button))
    } else {
      const textarea = document.createElement("textarea")
      textarea.value = text
      textarea.style.position = "fixed"
      textarea.style.opacity = "0"
      document.body.appendChild(textarea)
      textarea.select()
      document.execCommand("copy")
      document.body.removeChild(textarea)
      this.showFeedback(button)
    }
  }

  /** Brief visual feedback on the button after a successful copy. */
  showFeedback(button) {
    if (!button) return
    const originalHTML = button.innerHTML
    button.innerHTML = '<i class="ti ti-check"></i>'
    button.classList.add("text-success")
    button.classList.remove("text-muted")
    setTimeout(() => {
      button.innerHTML = originalHTML
      button.classList.remove("text-success")
      button.classList.add("text-muted")
    }, 2000)
  }
}
