import { Controller } from "@hotwired/stimulus"

// Support Console sidebar and keyboard shortcuts:
//   - filters the conversation list as you type, hiding date groups left empty;
//   - hides / shows the sidebar (remembered per browser — a viewing preference only);
//   - Ctrl/Cmd+K starts a new chat, "/" jumps to the question box;
//   - keeps the list in step with the chat frame (Turbo Frame "support-console-thread"): highlights
//     the open conversation, adds a just-started one under Today, and falls back to a full visit
//     when a response has no frame (e.g. the not-authorized redirect to the dashboard).
const COLLAPSED_KEY = "supportConsole.sidebarCollapsed"

export default class extends Controller {
  static targets = ["conversation", "group", "newChat", "list", "empty"]

  connect() {
    // localStorage can be unavailable (private window, blocked storage): default to shown.
    try {
      if (localStorage.getItem(COLLAPSED_KEY) === "1") this.element.classList.add("sc-collapsed")
    } catch {}
    window.addEventListener("keydown", this.shortcut)
    this.element.addEventListener("turbo:frame-load", this.frameLoaded)
    this.element.addEventListener("turbo:frame-missing", this.frameMissing)
  }

  disconnect() {
    window.removeEventListener("keydown", this.shortcut)
    this.element.removeEventListener("turbo:frame-load", this.frameLoaded)
    this.element.removeEventListener("turbo:frame-missing", this.frameMissing)
  }

  frameLoaded = (event) => {
    if (event.target.id !== "support-console-thread") return
    const chat = event.target.querySelector("#support-console-chat")
    if (!chat) return
    const id = chat.dataset.sessionId

    // A conversation started by this question is not in the list yet: add it under Today.
    if (id && !this.conversationTargets.some((row) => row.dataset.sessionId === id)) this.addConversation(chat)

    // Highlight the open conversation (none for an empty New chat).
    this.conversationTargets.forEach((row) => {
      const active = row.dataset.sessionId === id
      row.classList.toggle("active", active)
      active ? row.setAttribute("aria-current", "page") : row.removeAttribute("aria-current")
    })

    // New chat: ready to type straight away.
    if (!id) document.getElementById("support-console-question")?.focus()
  }

  // The response had no matching frame (a redirect away from the console): show that page in full.
  frameMissing = (event) => {
    event.preventDefault()
    event.detail.visit(event.detail.response)
  }

  addConversation(chat) {
    if (this.hasEmptyTarget) this.emptyTarget.remove()

    let today = this.groupTargets.find((g) => g.dataset.group === "Today")
    if (!today) {
      today = document.createElement("div")
      today.className = "text-muted small px-3 pt-3 pb-1"
      today.dataset.supportConsoleSidebarTarget = "group"
      today.dataset.group = "Today"
      today.textContent = "Today"
      this.listTarget.prepend(today)
    }

    // Same markup as the server-rendered rows in show.html.erb.
    const row = document.createElement("a")
    row.href = chat.dataset.sessionUrl
    row.className = "sc-conversation d-block px-3 py-2 rounded-3 text-truncate"
    row.title = chat.dataset.sessionTitle || ""
    row.dataset.supportConsoleSidebarTarget = "conversation"
    row.dataset.turboFrame = "support-console-thread"
    row.dataset.sessionId = chat.dataset.sessionId
    const text = document.createElement("span")
    text.dataset.role = "first-question"
    text.textContent = chat.dataset.firstQuestion || "New conversation"
    row.append(text)
    today.after(row)
  }

  toggle() {
    const collapsed = this.element.classList.toggle("sc-collapsed")
    try { localStorage.setItem(COLLAPSED_KEY, collapsed ? "1" : "0") } catch {}
  }

  filter(event) {
    const query = event.target.value.trim().toLowerCase()
    // Show matching conversations.
    this.conversationTargets.forEach((row) => {
      row.classList.toggle("d-none", query !== "" && !row.textContent.toLowerCase().includes(query))
    })
    // A group label stays only if a conversation after it (before the next label) is visible.
    this.groupTargets.forEach((label) => {
      let visible = false
      for (let el = label.nextElementSibling; el && !this.groupTargets.includes(el); el = el.nextElementSibling) {
        if (!el.classList.contains("d-none")) { visible = true; break }
      }
      label.classList.toggle("d-none", !visible)
    })
  }

  shortcut = (event) => {
    // Ctrl/Cmd+K — new chat.
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k" && this.hasNewChatTarget) {
      event.preventDefault()
      this.newChatTarget.click()
      return
    }
    // "/" — focus the question box, unless already typing somewhere.
    if (event.key === "/" && !event.ctrlKey && !event.metaKey && !event.target.closest("input, textarea, select, [contenteditable]")) {
      const box = document.getElementById("support-console-question")
      if (box) {
        event.preventDefault()
        box.focus()
      }
    }
  }
}
