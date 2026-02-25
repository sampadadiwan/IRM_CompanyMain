import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "toggleBtn", "messages", "input", "spinner", "welcome", "sendBtn", "resizeHandle"]
  static values = {
    supportAgentId: Number,
    chattableType: String,
    chattableId: Number,
    sessionId: Number,
    expanded: { type: Boolean, default: false }
  }

  connect() {
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



  close() {
    this.expandedValue = false
    this.panelTarget.classList.add("d-none")
    this.toggleBtnTarget.classList.remove("d-none")
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
        this.appendMessage("assistant", res.response)
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
        res.messages.forEach(msg => this.appendMessage(msg.role, msg.content))
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

  // --- UI Helpers ---

  appendMessage(role, content) {
    const div = document.createElement("div")
    div.classList.add("d-flex", "mb-3")

    if (role === "user") {
      div.classList.add("justify-content-end")
      div.innerHTML = `<div class="bg-primary text-white rounded-4 py-2 px-3" style="max-width:80%; border-bottom-right-radius:4px!important">${this.escapeHtml(content)}</div>`
    } else {
      div.classList.add("justify-content-start")
      div.innerHTML = `<div class="bg-light rounded-4 py-2 px-3" style="max-width:80%; border-bottom-left-radius:4px!important">${this.formatMarkdown(content)}</div>`
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
  // Sanitize dangerous tags
  let html = text
    .replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '')
    .replace(/<iframe\b[^<]*(?:(?!<\/iframe>)<[^<]*)*<\/iframe>/gi, '')
    .replace(/<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>/gi, '')

  // Strip markdown code fences
  html = html.replace(/```\w*\s*/g, '')

  // Collapse multiple blank lines into one
  html = html.replace(/\n{3,}/g, '\n\n')

  // Apply markdown formatting
  html = html
    .replace(/\*\*(.*?)\*\*/g, "<strong>$1</strong>")
    .replace(/\*(.*?)\*/g, "<em>$1</em>")
    .replace(/`([^`]+)`/g, "<code>$1</code>")

  // Remove formatting whitespace between HTML tags
  html = html.replace(/>\s+</g, '><')

  // Convert remaining newlines to <br> (text content only)
  html = html.replace(/\n/g, "<br>")

  return html
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
    return await res.json()
  }

  async getJSON(url) {
    const res = await fetch(url, {
      headers: { "Accept": "application/json" }
    })
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
    return await res.json()
  }
}
