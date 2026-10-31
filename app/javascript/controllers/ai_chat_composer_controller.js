import { Controller } from "@hotwired/stimulus"

// Chat kit question box (ai_chat/_composer): Enter sends, Shift+Enter adds a line, the box grows, a
// suggestion fills it (H14), and a second submit is blocked while a question is on its way (E4).
// The server is the real guard (e.g. SupportConsoleController#create_turn refuses a second turn) —
// this only stops a double click from sending two requests. After a turn ends the screen
// re-renders the composer, which reconnects this controller with running = false.
export default class extends Controller {
  static targets = ["question", "ask", "pending"]
  // pendingInto / emptyId: where a pending question + "Thinking…" go on submit, for screens whose
  // answer comes back with the response itself (the floating window); see ai_chat/_composer.
  static values = { running: Boolean, pendingInto: String, emptyId: String }

  connect() {
    // E4 — while a turn runs the composer renders Stop instead of Ask; guard Ask anyway.
    if (this.hasAskTarget) this.askTarget.disabled = this.runningValue
    if (this.hasQuestionTarget) {
      this.resize()
      // X4 — a question put back after a failure is ready to resend: focus at its end.
      if (this.questionTarget.value) {
        this.questionTarget.focus()
        this.questionTarget.setSelectionRange(this.questionTarget.value.length, this.questionTarget.value.length)
      }
    }
  }

  ask(event) {
    // E2 — an empty box is refused server-side too; skip the round trip.
    if (this.hasQuestionTarget && this.questionTarget.value.trim() === "") {
      event.preventDefault()
      return
    }
    if (this.hasAskTarget) this.askTarget.disabled = true
    this.showPending()
  }

  // Once Turbo has taken the form's data: clear the box. Ask stays disabled until the screen re-renders
  // the box (the answer's job, or the window's response), which also puts back a failed question.
  sent() {
    if (!this.hasQuestionTarget) return
    this.questionTarget.value = ""
    this.resize()
  }

  // Shows the question and a "Thinking…" line at once, from the composer's <template>, while the
  // request runs; the response replaces them.
  showPending() {
    if (!this.hasPendingTarget || !this.pendingIntoValue) return
    const list = document.getElementById(this.pendingIntoValue)
    if (!list) return
    const pending = this.pendingTarget.content.cloneNode(true)
    const question = pending.querySelector(".aic-question")
    if (question) question.textContent = this.questionTarget.value.trim()
    if (this.emptyIdValue) document.getElementById(this.emptyIdValue)?.remove()
    list.append(pending)
  }

  // Enter sends, Shift+Enter adds a new line (IME composition is left alone).
  keydown(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return
    event.preventDefault()
    // Nothing to send while a turn runs — Stop is the only action then.
    if (!this.hasAskTarget || this.askTarget.disabled) return
    this.questionTarget.form.requestSubmit(this.askTarget)
  }

  // H14 — a follow-up button puts its question in the box, ready to send or edit (it never sends).
  fill(event) {
    if (!this.hasQuestionTarget) return
    const box = this.questionTarget
    box.value = event.currentTarget.dataset.prompt || ""
    this.resize()
    box.focus()
    box.setSelectionRange(box.value.length, box.value.length)
  }

  // Grow the box with its content, up to the CSS max-height.
  resize() {
    const box = this.questionTarget
    box.style.height = "auto"
    box.style.height = `${box.scrollHeight}px`
  }
}
