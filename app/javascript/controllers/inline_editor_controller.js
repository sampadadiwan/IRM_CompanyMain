import { Controller } from "@hotwired/stimulus"

// Base controller for double-click inline editing with auto-save on blur.
//
// Usage: extend this class, override three methods:
//   get editableSelector()  — CSS selector for elements that should get hover hints
//   isNumberField(el)       — return true for elements that need a number <input>
//   collectPayload()        — return the object to send as the PATCH body
//
// The containing element needs:
//   data-controller="<name>"
//   data-<name>-url-value="<patch url>"
//   data-<name>-editable-value="true|false"   (false = read-only, no affordances)
//
// Editable elements need:
//   data-action="dblclick-><name>#startEdit"
//
// Optional saved badge (shown briefly on success):
//   data-<name>-target="savedBadge"
export default class extends Controller {
  static targets = ["savedBadge"]
  static values  = { url: String, editable: Boolean }

  connect() {
    if (!this.editableValue) return
    this.element.querySelectorAll(this.editableSelector)
      .forEach(el => el.classList.add("inline-editable"))
  }

  startEdit(event) {
    if (!this.editableValue) return
    const el = event.currentTarget
    if (el.contentEditable === "true" || el.tagName === "INPUT") return
    this.isNumberField(el) ? this.#makeNumberInput(el) : this.#makeContentEditable(el)
  }

  // ── Override these in subclasses ─────────────────────────────────────────

  // CSS selector for elements that receive the hover-hint class on connect.
  get editableSelector() { return "[data-field]" }

  // Return true if this element should become a number <input> instead of contenteditable.
  isNumberField(_el) { return false }

  // Build the JSON body sent on every save. Override in each subclass.
  collectPayload() { return {} }

  // Called right after an edited element's value is committed to the DOM,
  // before the save request fires. Override to update derived/dependent UI
  // (e.g. totals computed from the edited field) optimistically.
  onFieldChanged(_el) {}

  // ── Private ──────────────────────────────────────────────────────────────

  #makeContentEditable(el) {
    const original  = el.textContent.trim()
    const multiline = el.dataset.multiline === "true"
    el.contentEditable = "true"
    el.classList.add("inline-editing")
    el.focus()

    // Place cursor at end
    const range = document.createRange()
    range.selectNodeContents(el)
    range.collapse(false)
    window.getSelection().removeAllRanges()
    window.getSelection().addRange(range)

    const onBlur = () => {
      el.contentEditable = "false"
      el.classList.remove("inline-editing")
      el.removeEventListener("keydown", onKeydown)
      this.onFieldChanged(el)
      this.#save()
    }

    const onKeydown = (e) => {
      if (e.key === "Enter" && !multiline && !e.shiftKey) {
        e.preventDefault()
        el.blur()
      }
      if (e.key === "Escape") {
        el.removeEventListener("blur", onBlur)
        el.removeEventListener("keydown", onKeydown)
        el.contentEditable = "false"
        el.classList.remove("inline-editing")
        el.textContent = original
      }
    }

    el.addEventListener("blur",    onBlur,    { once: true })
    el.addEventListener("keydown", onKeydown)
  }

  #makeNumberInput(el) {
    const original  = parseInt(el.textContent.trim()) || 0
    const input     = document.createElement("input")
    input.type      = "number"
    input.value     = original
    input.min       = 0
    input.max       = 100
    input.className = "form-control form-control-sm inline-number-input"
    Object.assign(input.dataset, el.dataset) // preserve data attrs for collectPayload

    el.replaceWith(input)
    input.focus()
    input.select()

    const finish = () => {
      const val = Math.min(100, Math.max(0, parseInt(input.value) || 0))
      el.textContent = val
      input.replaceWith(el)
      this.onFieldChanged(el)
      this.#save()
    }

    input.addEventListener("blur", finish, { once: true })
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") { e.preventDefault(); input.blur() }
      if (e.key === "Escape") {
        input.removeEventListener("blur", finish)
        el.textContent = original
        input.replaceWith(el)
      }
    })
  }

  async #save() {
    try {
      const res = await fetch(this.urlValue, {
        method:  "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
        },
        body: JSON.stringify(this.collectPayload())
      })
      if (res.ok) this.#showSavedBadge()
      else console.error(`[InlineEditor] Save failed: ${res.status}`)
    } catch (err) {
      console.error("[InlineEditor] Network error:", err)
    }
  }

  #showSavedBadge() {
    if (!this.hasSavedBadgeTarget) return
    this.savedBadgeTarget.classList.remove("d-none")
    setTimeout(() => this.savedBadgeTarget.classList.add("d-none"), 2500)
  }
}
