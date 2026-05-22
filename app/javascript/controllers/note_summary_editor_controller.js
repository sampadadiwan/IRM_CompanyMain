import InlineEditorController from "./inline_editor_controller"
import { marked } from "marked"

// Inline editor for NoteSummarizerAgent summary text.
// Unlike the base class (which uses contenteditable spans), this controller
// swaps the rendered-HTML display div for a raw-markdown textarea on edit,
// then re-renders locally with marked on save — no server roundtrip for display.
export default class extends InlineEditorController {
  static targets = ["savedBadge", "displayArea", "editArea"]
  static values  = { url: String, editable: Boolean, reportId: Number }

  connect() {
    if (!this.editableValue) return
    if (this.hasDisplayAreaTarget) {
      this.displayAreaTarget.classList.add("inline-editable")
    }
  }

  // Override base startEdit — use textarea instead of contenteditable
  startEdit(event) {
    if (!this.editableValue) return
    if (!this.hasDisplayAreaTarget || !this.hasEditAreaTarget) return

    this.displayAreaTarget.classList.add("d-none")
    this.editAreaTarget.classList.remove("d-none")
    this.editAreaTarget.focus()

    // Cmd/Ctrl+Enter or blur saves; Escape cancels
    const onBlur = () => {
      this.editAreaTarget.removeEventListener("keydown", onKeydown)
      this.#finishEdit()
    }
    const onKeydown = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
        e.preventDefault()
        this.editAreaTarget.removeEventListener("blur", onBlur)
        this.editAreaTarget.removeEventListener("keydown", onKeydown)
        this.#finishEdit()
      }
      if (e.key === "Escape") {
        this.editAreaTarget.removeEventListener("blur", onBlur)
        this.editAreaTarget.removeEventListener("keydown", onKeydown)
        this.#cancelEdit()
      }
    }

    this.editAreaTarget.addEventListener("blur",    onBlur,    { once: true })
    this.editAreaTarget.addEventListener("keydown", onKeydown)
  }

  // collectPayload is used by base #save — not called here, but must be defined
  collectPayload() {
    return {
      report_id:    this.reportIdValue,
      summary_text: this.hasEditAreaTarget ? this.editAreaTarget.value : ""
    }
  }

  // ── Private ──────────────────────────────────────────────────────────────

  async #finishEdit() {
    const rawMarkdown = this.editAreaTarget.value

    // Swap back to display immediately (optimistic)
    this.editAreaTarget.classList.add("d-none")
    this.displayAreaTarget.classList.remove("d-none")

    // Re-render markdown locally so the user sees updated content right away
    this.displayAreaTarget.innerHTML = marked.parse(rawMarkdown || "")

    // Persist to server
    try {
      const res = await fetch(this.urlValue, {
        method:  "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
        },
        body: JSON.stringify(this.collectPayload())
      })
      if (res.ok) {
        // Keep textarea value in sync for next edit session
        this.editAreaTarget.value = rawMarkdown
        this.#showSavedBadge()
      } else {
        console.error("[NoteSummaryEditor] Save failed:", res.status)
      }
    } catch (err) {
      console.error("[NoteSummaryEditor] Network error:", err)
    }
  }

  #cancelEdit() {
    this.editAreaTarget.classList.add("d-none")
    this.displayAreaTarget.classList.remove("d-none")
  }

  #showSavedBadge() {
    if (!this.hasSavedBadgeTarget) return
    this.savedBadgeTarget.classList.remove("d-none")
    setTimeout(() => this.savedBadgeTarget.classList.add("d-none"), 2500)
  }
}
