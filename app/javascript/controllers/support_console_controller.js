import { Controller } from "@hotwired/stimulus"

// Support Console composer: blocks a second submit while a question is on its way (E4).
// The server is the real guard — SupportConsoleController#create_turn refuses a second turn —
// this only stops a double click from sending two requests. After a turn ends the job
// re-renders the composer, which reconnects this controller with running = false.
export default class extends Controller {
  static targets = ["question", "ask"]
  static values = { running: Boolean }

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
  }

  // Enter sends, Shift+Enter adds a new line (IME composition is left alone).
  keydown(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return
    event.preventDefault()
    // Nothing to send while a turn runs — Stop is the only action then.
    if (!this.hasAskTarget || this.askTarget.disabled) return
    this.questionTarget.form.requestSubmit(this.askTarget)
  }

  // Grow the box with its content, up to the CSS max-height.
  resize() {
    const box = this.questionTarget
    box.style.height = "auto"
    box.style.height = `${box.scrollHeight}px`
  }
}
