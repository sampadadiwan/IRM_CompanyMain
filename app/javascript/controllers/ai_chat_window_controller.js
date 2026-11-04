import { Controller } from "@hotwired/stimulus"

// The floating agent chat window (support_agents/_chat_panel): the "Need help?" bubble, and a window
// that can be dragged by its header, resized from any edge, maximised and closed. Its inside is the
// chat kit, loaded into a Turbo Frame when the window first opens. Window parts of the former
// agent_chat_controller.js; messages are now server-rendered (openspec/changes/ai-chat-kit, card ⑥).
const EDGE_PX = 8

export default class extends Controller {
  static targets = ["panel", "toggle"]
  // contentContainer: a page element given .chat-open while the window is open (host pages that
  // make room for it).
  static values = { contentContainer: { type: String, default: "" } }

  connect() {
    this.maximized = false
    this.onMouseMove = this.mouseMove.bind(this)
    this.onMouseUp = this.mouseUp.bind(this)
    // Opening a conversation (or New) from the Conversations view reloads the frame: show its chat.
    this.onFrameLoad = () => this.panelTarget.classList.remove("aic-show-list")
    this.panelTarget.addEventListener("turbo:frame-load", this.onFrameLoad)
  }

  disconnect() {
    this.mouseUp()
    this.panelTarget.removeEventListener("turbo:frame-load", this.onFrameLoad)
  }

  open() {
    this.panelTarget.classList.remove("d-none")
    this.toggleTarget.classList.add("d-none")
    this.contentContainer()?.classList.add("chat-open")
    // A lazy frame loads once it is visible; focus the box when it is there.
    this.panelTarget.querySelector("[data-ai-chat-composer-target='question']")?.focus()
  }

  close() {
    this.panelTarget.classList.add("d-none")
    this.toggleTarget.classList.remove("d-none")
    this.contentContainer()?.classList.remove("chat-open")
  }

  // Conversations: swaps the thread for the list of this record's conversations (and back).
  toggleList() {
    this.panelTarget.classList.toggle("aic-show-list")
  }

  // Maximise: the window fills the screen and shows the list beside the thread (H12).
  toggleMaximize() {
    const panel = this.panelTarget
    this.maximized = !this.maximized
    if (this.maximized) {
      // Remember a dragged/resized position so Restore puts it back.
      this.savedStyle = panel.getAttribute("style") || ""
      panel.setAttribute("style", "top: 0; left: 0; right: 0; bottom: 0; width: 100vw; height: 100vh; max-height: 100vh;")
    } else {
      panel.setAttribute("style", this.savedStyle || "")
    }
    panel.classList.toggle("aic-maximized", this.maximized)
    panel.classList.remove("aic-show-list")
  }

  // Drag by the header (buttons and links excepted).
  startDrag(event) {
    if (this.maximized || event.target.closest("button, a, select, input, textarea")) return
    event.preventDefault()
    const rect = this.panelTarget.getBoundingClientRect()
    this.drag = { x: event.clientX, y: event.clientY, left: rect.left, top: rect.top }
    this.listen()
  }

  // Resize from an edge (the panel's mousedown; ignored away from the edges).
  startResize(event) {
    if (this.maximized) return
    const edges = this.edgesAt(event)
    if (!edges) return
    event.preventDefault()
    const panel = this.panelTarget
    const rect = panel.getBoundingClientRect()
    this.resize = { edges, x: event.clientX, y: event.clientY, rect }
    // Pin the window by its top-left so every edge moves predictably.
    Object.assign(panel.style, { left: `${rect.left}px`, top: `${rect.top}px`, right: "auto", bottom: "auto" })
    this.listen()
  }

  // Resize cursor near the edges.
  updateCursor(event) {
    if (this.drag || this.resize) return
    const e = this.edgesAt(event)
    this.panelTarget.style.cursor = !e ? "" :
      (e.top && e.left) || (e.bottom && e.right) ? "nwse-resize" :
      (e.top && e.right) || (e.bottom && e.left) ? "nesw-resize" :
      e.left || e.right ? "ew-resize" : "ns-resize"
  }

  mouseMove(event) {
    const panel = this.panelTarget
    if (this.drag) {
      const left = Math.max(0, Math.min(this.drag.left + event.clientX - this.drag.x, window.innerWidth - panel.offsetWidth))
      const top = Math.max(0, Math.min(this.drag.top + event.clientY - this.drag.y, window.innerHeight - panel.offsetHeight))
      Object.assign(panel.style, { left: `${left}px`, top: `${top}px`, right: "auto", bottom: "auto" })
    } else if (this.resize) {
      const { edges, rect } = this.resize
      const dx = event.clientX - this.resize.x
      const dy = event.clientY - this.resize.y
      if (edges.right) panel.style.width = `${Math.max(320, rect.width + dx)}px`
      if (edges.bottom) panel.style.height = `${Math.max(400, rect.height + dy)}px`
      if (edges.left) {
        const width = Math.max(320, rect.width - dx)
        Object.assign(panel.style, { width: `${width}px`, left: `${rect.right - width}px` })
      }
      if (edges.top) {
        const height = Math.max(400, rect.height - dy)
        Object.assign(panel.style, { height: `${height}px`, top: `${rect.bottom - height}px`, maxHeight: "none" })
      }
    }
  }

  mouseUp() {
    this.drag = null
    this.resize = null
    document.removeEventListener("mousemove", this.onMouseMove)
    document.removeEventListener("mouseup", this.onMouseUp)
  }

  listen() {
    document.addEventListener("mousemove", this.onMouseMove)
    document.addEventListener("mouseup", this.onMouseUp)
  }

  // Which edges the pointer is within EDGE_PX of, or null.
  edgesAt(event) {
    const rect = this.panelTarget.getBoundingClientRect()
    const edges = {
      left: event.clientX - rect.left < EDGE_PX,
      top: event.clientY - rect.top < EDGE_PX,
      right: rect.right - event.clientX < EDGE_PX,
      bottom: rect.bottom - event.clientY < EDGE_PX
    }
    return Object.values(edges).some(Boolean) ? edges : null
  }

  contentContainer() {
    return this.contentContainerValue ? document.querySelector(this.contentContainerValue) : null
  }
}
