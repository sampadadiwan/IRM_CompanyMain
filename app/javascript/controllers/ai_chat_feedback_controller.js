import { Controller } from "@hotwired/stimulus"

// 👍 / 👎 under a Customer Support agent answer (ai_chat/_feedback): saves the rating through the
// unchanged feedback endpoint (SupportAgentChatFeedbacksController#update), and after 👎 asks what was
// wrong. Moved from the former agent_chat_controller's rateFeedback / submitFeedbackNote.
export default class extends Controller {
  static targets = ["up", "down", "note", "noteInput", "thanks"]
  static values = { url: String, rating: String }

  connect() {
    this.show(this.ratingValue)
  }

  async rate(event) {
    const rating = event.currentTarget.dataset.rating
    this.show(rating)
    this.thanksTarget.classList.add("d-none")
    // 👎 asks what was wrong; 👍 clears any earlier note.
    this.noteTarget.classList.toggle("d-none", rating !== "negative")
    if (rating === "negative") this.noteInputTarget.focus()
    await this.save(rating === "positive" ? { rating, notes: "" } : { rating })
  }

  async sendNote() {
    const notes = this.noteInputTarget.value.trim()
    if (!notes) return
    await this.save({ notes })
    this.noteTarget.classList.add("d-none")
    this.thanksTarget.classList.remove("d-none")
  }

  // The chosen rating is coloured; the other is plain.
  show(rating) {
    this.upTarget.classList.toggle("text-primary", rating === "positive")
    this.upTarget.classList.toggle("bg-primary-subtle", rating === "positive")
    this.upTarget.setAttribute("aria-pressed", rating === "positive")
    this.downTarget.classList.toggle("text-danger", rating === "negative")
    this.downTarget.classList.toggle("bg-danger-subtle", rating === "negative")
    this.downTarget.setAttribute("aria-pressed", rating === "negative")
  }

  async save(body) {
    const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
    try {
      await fetch(this.urlValue, {
        method: "PATCH",
        headers: { "X-CSRF-Token": token, "Content-Type": "application/json", "Accept": "application/json" },
        body: JSON.stringify(body)
      })
    } catch (err) {
      console.error("Failed to save feedback:", err)
    }
  }
}
