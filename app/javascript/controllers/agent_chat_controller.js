import { Controller } from "@hotwired/stimulus"
import { marked } from "marked"
import DOMPurify from "dompurify"

marked.setOptions({ gfm: true, breaks: true })

DOMPurify.addHook("afterSanitizeAttributes", (node) => {
  if (node.tagName === "A") {
    node.setAttribute("target", "_blank")
    node.setAttribute("rel", "noopener noreferrer")
  }
})




export default class extends Controller {
  static targets = ["panel", "toggleBtn", "messages", "input", "spinner", "welcome", "sendBtn", "resizeHandle", "maximizeIcon", "maximizeLabel" , "maximizeBtn", "sessionList"]
  static values = {
    supportAgentId: Number,
    chattableType: String,
    chattableId: Number,
    sessionId: Number,
    expanded: { type: Boolean, default: false },
    contentContainer: { type: String, default: "" },
    feedbackEnabled: { type: Boolean, default: false }


  }

  connect() {
    this.isMaximized = false
    this.historyLoaded = false
    this._onMouseMove = this.handleMouseMove.bind(this)
    this._onMouseUp = this.stopResize.bind(this)
  }

  handleMouseMove(e) {
    if (this.isResizing) {
      this.doResize(e)
    } else if (this.isDragging) {
      this.doDrag(e)
    }
  }


  toggle() {
  this.expandedValue = !this.expandedValue
  this.panelTarget.classList.toggle("d-none", !this.expandedValue)
  this.toggleBtnTarget.classList.toggle("d-none", this.expandedValue)

  const container = this.contentContainerValue ? document.querySelector(this.contentContainerValue) : null
  if (container) container.classList.toggle("chat-open", this.expandedValue)

  if (this.expandedValue && !this.historyLoaded) {
    this.loadHistory()
  }
}


    // Called on mousedown on the panel itself
  startResize(e) {
    const panel = this.panelTarget
    const rect = panel.getBoundingClientRect()
    const edge = 8 // pixels from edge to trigger resize

    const onLeft = e.clientX - rect.left < edge
    const onTop = e.clientY - rect.top < edge
    const onRight = rect.right - e.clientX < edge
    const onBottom = rect.bottom - e.clientY < edge

    if (!onLeft && !onTop && !onRight && !onBottom) return // not on edge

    e.preventDefault()
    this.isResizing = true
    this.resizeEdge = { left: onLeft, top: onTop, right: onRight, bottom: onBottom }
    this.startX = e.clientX
    this.startY = e.clientY
    this.startWidth = panel.offsetWidth
    this.startHeight = panel.offsetHeight
    this.startBottom = parseInt(panel.style.bottom) || 90
    this.startRight = parseInt(panel.style.right) || 24

    document.addEventListener("mousemove", this._onMouseMove)
    document.addEventListener("mouseup", this._onMouseUp)
  }

  doResize(e) {
    const dx = e.clientX - this.startX
    const dy = e.clientY - this.startY
    const panel = this.panelTarget

    if (this.resizeEdge.left) {
      panel.style.width = `${Math.max(320, this.startWidth - dx)}px`
    }
    if (this.resizeEdge.right) {
      const newWidth = Math.max(320, this.startWidth + dx)
      panel.style.width = `${newWidth}px`
      panel.style.right = `${Math.max(0, this.startRight - dx)}px`
    }
    if (this.resizeEdge.top) {
      panel.style.height = `${Math.max(400, this.startHeight - dy)}px`
    }
    if (this.resizeEdge.bottom) {
      const newHeight = Math.max(400, this.startHeight + dy)
      panel.style.height = `${newHeight}px`
      panel.style.bottom = `${Math.max(0, this.startBottom - dy)}px`
    }
  }

  stopResize() {
    this.isResizing = false
    document.removeEventListener("mousemove", this._onMouseMove)
    document.removeEventListener("mouseup", this._onMouseUp)
  }

  startDrag(e) {
  if (e.target.closest('button')) return
  e.preventDefault()
  const rect = this.panelTarget.getBoundingClientRect()
  this.isDragging = true
  this.dragStartX = e.clientX
  this.dragStartY = e.clientY
  this.dragStartLeft = rect.left
  this.dragStartTop = rect.top
  this.panelTarget.style.cursor = 'grabbing'
  document.addEventListener('mousemove', this._onMouseMove)
  document.addEventListener('mouseup', this._onMouseUp)
}

  doDrag(e) {
    const dx = e.clientX - this.dragStartX
    const dy = e.clientY - this.dragStartY
    const panel = this.panelTarget
    const newLeft = Math.max(0, Math.min(this.dragStartLeft + dx, window.innerWidth - panel.offsetWidth))
    const newTop = Math.max(0, Math.min(this.dragStartTop + dy, window.innerHeight - panel.offsetHeight))
    panel.style.left = `${newLeft}px`
    panel.style.top = `${newTop}px`
    panel.style.right = 'auto'
    panel.style.bottom = 'auto'
  }

  stopDrag() {
    this.isDragging = false
    this.panelTarget.style.cursor = ''
    document.removeEventListener('mousemove', this._onMouseMove)
    document.removeEventListener('mouseup', this._onMouseUp)
  }


  // Show resize cursor when hovering near edges
  updateCursor(e) {
    const panel = this.panelTarget
    const rect = panel.getBoundingClientRect()
    const edge = 8

    const onLeft = e.clientX - rect.left < edge
    const onTop = e.clientY - rect.top < edge
    const onRight = rect.right - e.clientX < edge
    const onBottom = rect.bottom - e.clientY < edge

    if ((onTop && onLeft) || (onBottom && onRight)) panel.style.cursor = "nwse-resize"
    else if ((onTop && onRight) || (onBottom && onLeft)) panel.style.cursor = "nesw-resize"
    else if (onLeft || onRight) panel.style.cursor = "ew-resize"
    else if (onTop || onBottom) panel.style.cursor = "ns-resize"
    else panel.style.cursor = "default"
  }


/**
 * Toggles the chat panel between its floating size and full-screen.
 * Saves the prior inline styles on maximize and restores them on minimize,
 * so manual drag/resize positions survive the round-trip.
 *
 * @returns {void}
 */
toggleMaximize() {
  const panel = this.panelTarget

  if (!this.isMaximized) {
    this.savedStyles = {
      width: panel.style.width,
      height: panel.style.height,
      top: panel.style.top,
      left: panel.style.left,
      right: panel.style.right,
      bottom: panel.style.bottom,
      maxHeight: panel.style.maxHeight,
      borderRadius: panel.style.borderRadius
    }

    panel.style.top = "0"
    panel.style.left = "0"
    panel.style.right = "0"
    panel.style.bottom = "0"
    panel.style.width = "100vw"
    panel.style.height = "100vh"
    panel.style.maxHeight = "100vh"
    panel.style.borderRadius = "0"

    if (this.hasMaximizeIconTarget) {
      this.maximizeIconTarget.classList.remove("bi-arrows-fullscreen")
      this.maximizeIconTarget.classList.add("bi-arrows-angle-contract")
    }
    if (this.hasMaximizeLabelTarget) this.maximizeLabelTarget.textContent = "Restore"

    this.isMaximized = true
  } else {
    Object.assign(panel.style, this.savedStyles || {})

    if (this.hasMaximizeIconTarget) {
      this.maximizeIconTarget.classList.remove("bi-arrows-angle-contract")
      this.maximizeIconTarget.classList.add("bi-arrows-fullscreen")
    }
    if (this.hasMaximizeLabelTarget) this.maximizeLabelTarget.textContent = "Maximize"

    this.isMaximized = false
  }
}

close() {
  this.expandedValue = false
  this.panelTarget.classList.add("d-none")
  this.toggleBtnTarget.classList.remove("d-none")

  const container = this.contentContainerValue ? document.querySelector(this.contentContainerValue) : null
  if (container) container.classList.remove("chat-open")
}

/**
 * Pre-fills the chat input with the clicked sample-question chip's prompt
 * and focuses the textarea. Used by chips inside the panel's welcome state.
 *
 * @param {MouseEvent} e - Click event from a chip; reads `data-prompt`.
 * @returns {void}
 */
fillPrompt(e) {
  this.inputTarget.value = e.currentTarget.dataset.prompt
  this.inputTarget.focus()
}




  handleEnter(e) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault()
      this.sendMessage()
    }
  }

  async sendMessage() {
    const message = (this.inputTarget.value || "").trim()
    if (!message) return

    this.hideWelcome()
    this.appendMessage("user", message)
    this.inputTarget.value = ""
    this.messagesTarget.appendChild(this.spinnerTarget)
    this.showSpinner()
    this.scrollToBottom()


    this.sendBtnTarget.disabled = true

    try {
      const res = await this.postJSON(this.chatsUrl(), {
        message,
        chattable_type: this.chattableTypeValue,
        chattable_id: this.chattableIdValue
      })

      if (res.success) {
        this.sessionIdValue = res.session_id
        this.appendMessage("assistant", res.response, res.message_id)

      } else {
        this.appendError(res.error || "Something went wrong")
      }
    } catch (err) {
      console.error(err)
      this.appendError("Failed to send message. Please try again.")
    } finally {
      this.hideSpinner()
      this.sendBtnTarget.disabled = false
      this.scrollToBottom()
    }
  }

  async loadHistory() {
    try {
      const url = this.chatsUrl() + `?chattable_type=${this.chattableTypeValue}&chattable_id=${this.chattableIdValue}`
      const res = await this.getJSON(url)

      if (res.success && res.messages.length > 0) {
        this.hideWelcome()
        this.sessionIdValue = res.session_id
        res.messages.forEach(msg => this.appendMessage(msg.role, msg.content, msg.id, msg.feedback_rating))

        this.scrollToBottom()
      }
      this.historyLoaded = true
    } catch (err) {
      console.error("Failed to load chat history:", err)
    }
  }

  async clearChat() {
    if (!this.sessionIdValue) return
    if (!confirm("Clear chat history?")) return

    try {
      await this.deleteJSON(`${this.chatsUrl()}/${this.sessionIdValue}`)
      Array.from(this.messagesTarget.children).forEach(child => {
        if (!child.hasAttribute('data-agent-chat-target')) child.remove()
      })
      this.sessionIdValue = 0
      this.showWelcome()
    } catch (err) {
      console.error("Failed to clear chat:", err)
    }
  }

  /**
 * Toggles the session history sidebar. Loads session list from the server
 * on first open. Allows users to see and switch between past conversations.
 *
 * @returns {void}
 */
async toggleSessions() {
  const list = this.sessionListTarget
  const isVisible = !list.classList.contains("d-none")

  if (isVisible) {
    list.classList.add("d-none")
    return
  }

  list.classList.remove("d-none")
  list.innerHTML = '<div class="p-2 text-muted small text-center">Loading sessions...</div>'

  try {
    const url = `/support_agents/${this.supportAgentIdValue}/chats/sessions?chattable_type=${this.chattableTypeValue}&chattable_id=${this.chattableIdValue}`
    const res = await this.getJSON(url)

    if (res.success && res.sessions.length > 0) {
      list.innerHTML = res.sessions.map(s => {
        const date = new Date(s.updated_at)
        // undefined locale = the visitor's own browser/OS locale, not a hardcoded region.
        const dateStr = date.toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" })
        const isActive = s.id === this.sessionIdValue
        const statusBadge = s.status === "escalated" ? '<span class="badge bg-warning text-dark ms-1" style="font-size:0.65rem">Escalated</span>' : ""

        return `
          <div class="d-flex align-items-center px-3 py-2 border-bottom session-item ${isActive ? 'bg-light' : ''}"
               style="cursor: pointer; ${isActive ? 'border-left: 3px solid var(--bs-primary);' : ''}"
               data-action="click->agent-chat#switchSession"
               data-session-id="${s.id}">
            <div class="flex-grow-1 overflow-hidden">
              <div class="small fw-semibold text-truncate">${this.escapeHtml(s.preview || "New conversation")}</div>
              <div class="text-muted" style="font-size:0.7rem">${dateStr} · ${s.message_count} msgs ${statusBadge}</div>
            </div>
            ${isActive ? '<i class="bi bi-check-circle-fill text-primary ms-2"></i>' : ''}
          </div>
        `
      }).join("")
    } else {
      list.innerHTML = '<div class="p-3 text-muted small text-center">No past sessions</div>'
    }
  } catch (err) {
    console.error("Failed to load sessions:", err)
    list.innerHTML = '<div class="p-3 text-danger small text-center">Failed to load sessions</div>'
  }
}

/**
 * Switches to a different chat session. Clears the current messages,
 * loads the selected session's history, and updates the session ID.
 *
 * @param {MouseEvent} e - Click event from a session item; reads data-session-id.
 * @returns {void}
 */
async switchSession(e) {
  const sessionId = e.currentTarget.dataset.sessionId
  if (!sessionId || parseInt(sessionId) === this.sessionIdValue) return

  // Clear current messages
  Array.from(this.messagesTarget.children).forEach(child => {
    if (!child.hasAttribute('data-agent-chat-target')) child.remove()
  })

  // Load the selected session's messages
  try {
    const url = this.chatsUrl() + `?chattable_type=${this.chattableTypeValue}&chattable_id=${this.chattableIdValue}&session_id=${sessionId}`
    const res = await this.getJSON(url)

    if (res.success && res.messages.length > 0) {
      this.hideWelcome()
      this.sessionIdValue = res.session_id
      res.messages.forEach(msg => this.appendMessage(msg.role, msg.content, msg.id, msg.feedback_rating))
      this.scrollToBottom()
    } else {
      this.sessionIdValue = parseInt(sessionId)
      this.showWelcome()
    }
  } catch (err) {
    console.error("Failed to switch session:", err)
  }

  // Collapse the session list
  this.sessionListTarget.classList.add("d-none")
}

/**
 * Starts a new chat session. Clears the current messages and resets
 * the session ID to 0 so the next message creates a fresh session
 * on the backend (via GenericChatAgent's session auto-expire logic).
 *
 * @returns {void}
 */
newChat() {
  // Clear current messages
  Array.from(this.messagesTarget.children).forEach(child => {
    if (!child.hasAttribute('data-agent-chat-target')) child.remove()
  })

  this.sessionIdValue = 0
  this.showWelcome()
  this.sessionListTarget.classList.add("d-none")
  this.inputTarget.focus()
}


  // --- UI Helpers ---

  appendMessage(role, content, messageId, feedbackRating) {
    const div = document.createElement("div")
    div.classList.add("d-flex", "mb-3")

    if (role === "user") {
      div.classList.add("justify-content-end")
      div.innerHTML = `<div class="bg-primary text-white rounded-4 py-2 px-3" style="max-width:80%; border-bottom-right-radius:4px!important">${this.escapeHtml(content)}</div>`
        } else {
      div.classList.add("justify-content-start")
      div.innerHTML = `
        <div style="max-width:80%;">
          <div class="bg-light rounded-4 py-2 px-3" style="border-bottom-left-radius:4px!important">${this.formatMarkdown(content)}</div>
          ${messageId && this.feedbackEnabledValue ? this.feedbackRowHtml(messageId, feedbackRating) : ""}
        </div>
      `
    }


    this.messagesTarget.appendChild(div)
    this.scrollToBottom()
  }


  appendError(msg) {
    const html = `<div class="text-center text-danger small my-2">${this.escapeHtml(msg)}</div>`
    this.messagesTarget.insertAdjacentHTML("beforeend", html)
  }

  showSpinner() {
    if (this.hasSpinnerTarget) this.spinnerTarget.classList.remove("d-none")
  }

  hideSpinner() {
    if (this.hasSpinnerTarget) this.spinnerTarget.classList.add("d-none")
  }

  hideWelcome() {
    if (this.hasWelcomeTarget) this.welcomeTarget.classList.add("d-none")
  }

  showWelcome() {
    if (this.hasWelcomeTarget) this.welcomeTarget.classList.remove("d-none")
  }

  scrollToBottom() {
    setTimeout(() => {
      this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
    }, 50)
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }

formatMarkdown(text) {
  const rawHtml = marked.parse(text || "")
  return DOMPurify.sanitize(rawHtml, {
    ADD_ATTR: ["target", "rel"]
  })
}

  feedbackRowHtml(messageId, feedbackRating) {
    const upClass = feedbackRating === "positive" ? "text-primary" : "text-muted"
    const downClass = feedbackRating === "negative" ? "text-danger" : "text-muted"
    return `
      <div class="d-flex align-items-center gap-3 mt-2 ms-2 feedback-row" data-message-id="${messageId}">
        <button class="btn btn-sm btn-link ${upClass} p-1" data-action="click->agent-chat#rateFeedback"
                data-rating="positive" data-message-id="${messageId}" title="Helpful" style="font-size: 1rem;">
          <i class="${feedbackRating === 'positive' ? 'fa-solid' : 'fa-regular'} fa-thumbs-up"></i>
        </button>
        <button class="btn btn-sm btn-link ${downClass} p-1" data-action="click->agent-chat#rateFeedback"
                data-rating="negative" data-message-id="${messageId}" title="Not helpful" style="font-size: 1rem;">
          <i class="${feedbackRating === 'negative' ? 'fa-solid' : 'fa-regular'} fa-thumbs-down"></i>
        </button>
      </div>
    `
  }


  async rateFeedback(e) {
    const btn = e.currentTarget
    const messageId = btn.dataset.messageId
    const rating = btn.dataset.rating
    const row = btn.closest(".feedback-row")

    // Optimistic UI — highlight selected, dim the other
    row.querySelectorAll("button").forEach(b => {
      b.classList.remove("text-primary", "text-danger")
      b.classList.add("text-muted")
      b.querySelector("i").classList.replace("fa-solid", "fa-regular")
    })
    btn.classList.remove("text-muted")
    btn.classList.add(rating === "positive" ? "text-primary" : "text-danger")
    btn.querySelector("i").classList.replace("fa-regular", "fa-solid")


    

    // Remove any existing note input or thanks message
    row.parentElement.querySelectorAll(".feedback-note-input").forEach(el => el.remove())



    // If negative, show inline note input
    if (rating === "negative" && !row.parentElement.querySelector(".feedback-note-input")) {
      const noteHtml = `
        <div class="d-flex align-items-center gap-1 mt-1 feedback-note-input" style="max-width:80%;">
          <input type="text" class="form-control form-control-sm" placeholder="What went wrong? (optional)"
                 data-message-id="${messageId}" style="font-size: 0.75rem;">
          <button class="btn btn-sm btn-outline-secondary" data-action="click->agent-chat#submitFeedbackNote"
                  data-message-id="${messageId}" style="font-size: 0.75rem;">Send</button>
        </div>
      `
      row.insertAdjacentHTML("afterend", noteHtml)
    }


    try {
      await this.patchJSON(`${this.chatsUrl()}/${messageId}/feedback`, { rating, notes: rating === "positive" ? "" : undefined })
    } catch (err) {

      console.error("Failed to save feedback:", err)
    }
  }

  async submitFeedbackNote(e) {
    const btn = e.currentTarget
    const messageId = btn.dataset.messageId
    const wrapper = btn.closest(".feedback-note-input")
    const input = wrapper.querySelector("input")
    const notes = (input.value || "").trim()

    if (!notes) return

    btn.disabled = true
    try {
      await this.patchJSON(`${this.chatsUrl()}/${messageId}/feedback`, { notes })
      wrapper.innerHTML = `<span class="text-muted small">Thanks for your feedback</span>`
    } catch (err) {
      console.error("Failed to save feedback note:", err)
      btn.disabled = false
    }
  }





  // --- HTTP Helpers ---

  chatsUrl() {
    return `/support_agents/${this.supportAgentIdValue}/chats`
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
  }

  async postJSON(url, data) {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "X-CSRF-Token": this.csrfToken(),
        "Content-Type": "application/json",
        "Accept": "application/json"
      },
      body: JSON.stringify(data)
    })
    if (!res.ok) throw new Error(`Request failed: ${res.status}`)
      return await res.json()

  }

  async getJSON(url) {
    const res = await fetch(url, {
      headers: { "Accept": "application/json" }
    })
    if (!res.ok) throw new Error(`Request failed: ${res.status}`)
      return await res.json()

  }

  async deleteJSON(url) {
    const res = await fetch(url, {
      method: "DELETE",
      headers: {
        "X-CSRF-Token": this.csrfToken(),
        "Accept": "application/json"
      }
    })
    if (!res.ok) throw new Error(`Request failed: ${res.status}`)
      return await res.json()

  }

    async patchJSON(url, data) {
    const res = await fetch(url, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": this.csrfToken(),
        "Content-Type": "application/json",
        "Accept": "application/json"
      },
      body: JSON.stringify(data)
    })
    if (!res.ok) throw new Error(`Request failed: ${res.status}`)
      return await res.json()

  }

}
