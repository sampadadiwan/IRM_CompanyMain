import { Controller } from "@hotwired/stimulus"

// Chat kit sidebar (ai_chat/_layout, ai_chat/_sidebar) and keyboard shortcuts:
//   - filters the conversation list as you type, hiding date groups left empty;
//   - hides / shows the sidebar (remembered per browser — a viewing preference only);
//   - Ctrl/Cmd+K starts a new chat, "/" jumps to the question box;
//   - keeps the list in step with the chat frame (the Turbo Frame named by frameValue): highlights
//     the open conversation, adds a just-started one under Today, and falls back to a full visit
//     when a response has no frame (e.g. the not-authorized redirect to the dashboard).
export default class extends Controller {
  static targets = ["conversation", "group", "newChat", "list", "empty"]
  // frame: the Turbo Frame the thread loads into; storageKey: where a hidden sidebar is remembered.
  // shortcuts: off in the floating window, so Ctrl+K and "/" stay with the page.
  static values = { frame: String, storageKey: { type: String, default: "aiChat.sidebarCollapsed" },
                    shortcuts: { type: Boolean, default: true } }

  connect() {
    // localStorage can be unavailable (private window, blocked storage): default to shown.
    try {
      if (localStorage.getItem(this.storageKeyValue) === "1") this.element.classList.add("aic-collapsed")
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
    if (event.target.id !== this.frameValue) return
    const chat = event.target.querySelector("[data-ai-chat-root]")
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
    if (!id) this.questionBox()?.focus()
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
      today.className = "small fw-normal text-body-secondary px-3 pt-3 pb-1"
      today.dataset.aiChatSidebarTarget = "group"
      today.dataset.group = "Today"
      today.textContent = "Today"
      this.listTarget.prepend(today)
    }

    // Same markup as ai_chat/_conversation. No status badge: the row is the open
    // conversation, whose thread shows its status (the CSS hides an open row's badge anyway).
    const title = (chat.dataset.firstQuestion || "").trim().replace(/^["'“‘]+/, "").replace(/["'”’]+$/, "") || "New conversation"
    const row = document.createElement("a")
    row.href = chat.dataset.sessionUrl
    row.className = "aic-conversation d-block fw-normal px-3 py-2 rounded-3"
    row.title = title
    row.dataset.aiChatSidebarTarget = "conversation"
    row.dataset.turboFrame = this.frameValue
    row.dataset.sessionId = chat.dataset.sessionId
    const text = document.createElement("span")
    text.className = "d-block text-truncate"
    text.dataset.role = "first-question"
    text.textContent = title
    const meta = document.createElement("span")
    meta.className = "d-flex align-items-center gap-2 small text-body-secondary"
    meta.dataset.role = "meta"
    const who = document.createElement("span")
    who.className = "text-truncate"
    who.textContent = chat.dataset.sessionMeta || ""
    meta.append(who)
    row.append(text, meta)
    today.after(row)
  }

  toggle() {
    const collapsed = this.element.classList.toggle("aic-collapsed")
    try { localStorage.setItem(this.storageKeyValue, collapsed ? "1" : "0") } catch {}
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
    if (!this.shortcutsValue) return
    // Ctrl/Cmd+K — new chat.
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k" && this.hasNewChatTarget) {
      event.preventDefault()
      this.newChatTarget.click()
      return
    }
    // "/" — focus the question box, unless already typing somewhere.
    if (event.key === "/" && !event.ctrlKey && !event.metaKey && !event.target.closest("input, textarea, select, [contenteditable]")) {
      const box = this.questionBox()
      if (box) {
        event.preventDefault()
        box.focus()
      }
    }
  }

  // The open thread's question box (ai_chat/_composer), wherever the screen puts it.
  questionBox() {
    return this.element.querySelector("[data-ai-chat-composer-target='question']")
  }
}
