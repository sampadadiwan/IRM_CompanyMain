import { Controller } from "@hotwired/stimulus"

// How long after a section opens its lazy frames may still pull it back to the top
const SETTLE_MS = 4000

// Brings the section the user just expanded to the top of the viewport.
// Attach to a Bootstrap `.accordion`; the sticky top bar is cleared via the
// item's `scroll-margin-top` (see lp_layout.scss).
export default class extends Controller {
  connect() {
    this.onShown = this.onShown.bind(this)
    this.onFrameLoad = this.onFrameLoad.bind(this)
    this.element.addEventListener("shown.bs.collapse", this.onShown)
    // Section bodies are lazy turbo frames — re-scroll as their content arrives
    this.element.addEventListener("turbo:frame-load", this.onFrameLoad)
    this.scrollToLinkedSection()
  }

  disconnect() {
    this.element.removeEventListener("shown.bs.collapse", this.onShown)
    this.element.removeEventListener("turbo:frame-load", this.onFrameLoad)
  }

  onShown(event) {
    // Ignore collapses nested inside a section's body — only react to the sections themselves
    if (event.target.parentElement?.parentElement !== this.element) return

    this.bringToTop(event.target.closest(".accordion-item"))
  }

  // A section opened near the bottom of the page can't reach the top while its body is still
  // a loading spinner (the page isn't tall enough yet). When its frame content lands, scroll again.
  onFrameLoad(event) {
    const item = event.target.closest(".accordion-item")
    if (!item || item !== this.activeItem) return
    if (Date.now() - this.openedAt > SETTLE_MS) return

    this.scrollItem(item)
  }

  // A ?tab=<id> link is opened by tabs_controller, which can run before this controller is
  // loaded — so its shown event may already have fired. Scroll to that section ourselves.
  scrollToLinkedSection() {
    const tab = new URLSearchParams(window.location.search).get("tab")
    const target = tab && document.getElementById(tab)
    if (!target || !this.element.contains(target)) return

    // The id may name the collapse itself or the section's header (e.g. docs-tab)
    const item = target.closest(".accordion-item")
    const collapse = item?.querySelector(":scope > .accordion-collapse")
    if (!collapse) return

    // Still opening (or not opened yet): the shown listener above will scroll when it finishes
    if (!collapse.classList.contains("show") || collapse.classList.contains("collapsing")) return

    this.bringToTop(item)
  }

  // Remember which section was opened and when, then scroll it up
  bringToTop(item) {
    if (!item) return
    this.activeItem = item
    this.openedAt = Date.now()
    this.scrollItem(item)
  }

  scrollItem(item) {
    // Wait a frame so the new content's height is laid out before measuring
    requestAnimationFrame(() => item.scrollIntoView({ behavior: "smooth", block: "start" }))
  }
}
