import { Controller } from "@hotwired/stimulus"

// Support Console message thread. SupportConsoleTurnJob replaces message elements over Turbo
// streams while an answer streams in; this controller keeps the view usable around that:
//   - follows the newest text while the reader is at the bottom, and offers "Jump to latest"
//     when they have scrolled up to read instead of yanking them down;
//   - keeps an open "steps" list or "Where this comes from" section open across the re-renders;
//   - right-aligns amount cells in answer tables and lets wide tables scroll sideways;
//   - shades the header once the thread is scrolled, and copies a message on its Copy button.
const NEAR_BOTTOM_PX = 80
// A cell that is only an amount or a number: ₹/$ signs, minus signs, digits, separators, %.
const NUMERIC_CELL = /^[-−–+(]?\s*[₹$€£]?\s*[-−]?\s*[\d.,]+\s*(%|cr|crore|lakh|L)?\)?$/i

export default class extends Controller {
  static targets = ["scroller", "jump", "header"]

  connect() {
    this.following = true
    this.openSteps = new Set()
    this.decorate()
    this.scrollToBottom()
    // Turbo stream replaces land as child-list changes inside the scroller.
    this.observer = new MutationObserver(() => this.changed())
    this.observer.observe(this.scrollerTarget, { childList: true, subtree: true })
    // Remember which collapsible sections are open so a re-render does not collapse them.
    this.scrollerTarget.addEventListener("toggle", this.rememberSteps, true)
  }

  disconnect() {
    this.observer?.disconnect()
    this.scrollerTarget.removeEventListener("toggle", this.rememberSteps, true)
  }

  rememberSteps = (event) => {
    const id = event.target.closest("[id^='agent_chat_message_']")?.id
    const kind = ["sc-steps", "sc-sources"].find((k) => event.target.matches(`details.${k}`))
    if (!id || !kind) return
    const key = `${id} details.${kind}`
    event.target.open ? this.openSteps.add(key) : this.openSteps.delete(key)
  }

  changed() {
    // Our own DOM edits also trigger the observer; pause it while decorating.
    this.observer.disconnect()
    this.decorate()
    this.observer.observe(this.scrollerTarget, { childList: true, subtree: true })
    if (this.following) this.scrollToBottom()
    else this.jumpTarget.classList.remove("d-none")
  }

  onScroll() {
    const el = this.scrollerTarget
    this.following = el.scrollHeight - el.scrollTop - el.clientHeight < NEAR_BOTTOM_PX
    if (this.following) this.jumpTarget.classList.add("d-none")
    // A faint header shadow only once content has scrolled under it.
    if (this.hasHeaderTarget) this.headerTarget.classList.toggle("sc-scrolled", el.scrollTop > 4)
  }

  // Copies a message's text (its markdown, for answers) and flashes a check on the button.
  async copy(event) {
    const button = event.currentTarget
    try {
      await navigator.clipboard.writeText(button.dataset.copyText || "")
    } catch {
      return // clipboard blocked (insecure origin or denied): leave the icon as it was
    }
    const icon = button.querySelector("i")
    icon.className = "ti ti-check"
    setTimeout(() => { icon.className = "ti ti-copy" }, 1500)
  }

  jumpToLatest() {
    this.following = true
    this.scrollToBottom()
    this.jumpTarget.classList.add("d-none")
  }

  scrollToBottom() {
    this.scrollerTarget.scrollTop = this.scrollerTarget.scrollHeight
  }

  decorate() {
    // Re-open sections the reader had open before the message was re-rendered.
    this.openSteps.forEach((key) => {
      const details = this.scrollerTarget.querySelector(`#${key}`)
      if (details && !details.open) details.open = true
    })

    this.scrollerTarget.querySelectorAll(".sc-answer table:not([data-decorated])").forEach((table) => {
      table.dataset.decorated = "true"
      // Wide tables scroll inside the bubble.
      const wrap = document.createElement("div")
      wrap.className = "chat-table-wrap"
      table.parentNode.insertBefore(wrap, table)
      wrap.appendChild(table)

      // Right-align a column when every non-empty body cell in it is a number.
      const rows = Array.from(table.querySelectorAll("tbody tr"))
      const columns = Math.max(0, ...rows.map((r) => r.cells.length))
      for (let i = 0; i < columns; i++) {
        const cells = rows.map((r) => r.cells[i]).filter((c) => c && c.textContent.trim() !== "")
        if (cells.length === 0 || !cells.every((c) => NUMERIC_CELL.test(c.textContent.trim()))) continue
        cells.forEach((c) => c.classList.add("text-end"))
        table.querySelector("thead tr")?.cells[i]?.classList.add("text-end")
      }
    })
  }
}
