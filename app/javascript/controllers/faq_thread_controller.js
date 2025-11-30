import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messages", "input", "typing", "message"]

  connect() {
    this.scrollToBottom()
  }

  submitOnEnter(event) {
    if (!event.shiftKey) {
      event.preventDefault()
      event.target.form.requestSubmit()
      this.showTypingIndicator()
    }
  }

  resetForm() {
    this.inputTarget.value = ""
    this.scrollToBottom()
  }

  messageTargetConnected(element) {
    this.scrollToBottom()
    if (element.dataset.role === 'assistant') {
      this.hideTypingIndicator()
    }
  }

  messagesTargetConnected() {
    this.scrollToBottom()
    this.hideTypingIndicator()
  }

  showTypingIndicator() {
    this.typingTarget.classList.remove('d-none')
    this.scrollToBottom()
  }

  hideTypingIndicator() {
    this.typingTarget.classList.add('d-none')
  }

  scrollToBottom() {
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }
}