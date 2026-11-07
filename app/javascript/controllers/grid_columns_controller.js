import { Controller } from "@hotwired/stimulus"
import { ensurePanel, bindEscape, showToast, refreshPage, restoreScroll, prefersReducedMotion } from "custom/side_panel"

// ①②⑥⑦ Table columns in place — openspec/changes/grid-columns-inline-settings (cards ①, ②, ⑥, ⑦; D8, D9, D18, D19).
// On a table's wrapper: puts the always-visible ▥ button next to the table's search box, loads the editor into the
// page's one side panel, and when the save answers with the saved marker closes the panel and reloads only this
// table's turbo frame. On the full Configure Grids page (data-grid-columns-embedded): a save refreshes the page.
const PANEL_ID = "grid_columns_panel"
const FRAME_ID = "grid_columns"
const HIGHLIGHT_MS = 1200

export default class extends Controller {
  connect() {
    // D16 — a page refreshed after a save comes back where it was, with its toast
    restoreScroll()
    if (this.element.dataset.gridColumnsEmbedded === "true") {
      this.listenEmbedded()
    } else {
      this.placeButton()
    }
  }

  disconnect() {
    this.stopListening()
    this.stopDtObserver()
    if (this.embeddedFrame) this.embeddedFrame.removeEventListener("turbo:frame-load", this.onEmbeddedLoad)
    // The button may have moved out of this wrapper; it goes with the table
    if (this.button && !this.element.contains(this.button)) this.button.remove()
  }

  // D18 — the ▥ button sits right of the search box when the table's frame has one, else at the table's top-right
  placeButton() {
    this.button = this.element.querySelector(":scope > .grid-columns-btn")
    if (!this.button) return
    this.onOpen = this.open.bind(this)
    this.button.addEventListener("click", this.onOpen)

    const frame = this.element.closest("turbo-frame")
    const search = frame?.querySelector(".search-form-input")
    if (!search) { this.placeBesideDataTablesSearch(); return }
    // Another table in the same frame already sits there: this one keeps its button at its own corner
    if (search.parentElement.querySelector(":scope > .grid-columns-btn")) return
    search.classList.add("ms-auto")
    this.button.classList.add("in-search", "btn", "btn-outline-secondary")
    search.after(this.button)
  }

  // D21 — a list sorted in the page by jQuery DataTables has no search component; DataTables draws its own
  // "Search:" box inside this wrapper once it initialises, so wait for it (briefly) and sit right of its input
  placeBesideDataTablesSearch() {
    const place = () => {
      const filter = this.element.querySelector(".dt-search, .dataTables_filter")
      if (!filter) return false
      if (!filter.querySelector(".grid-columns-btn")) {
        filter.classList.add("d-flex", "align-items-center", "justify-content-end")
        this.button.classList.add("in-search", "btn", "btn-outline-secondary")
        filter.appendChild(this.button)
      }
      return true
    }
    if (place()) return
    this.dtObserver = new MutationObserver(() => { if (place()) this.stopDtObserver() })
    this.dtObserver.observe(this.element, { childList: true, subtree: true })
    this.dtTimer = setTimeout(() => this.stopDtObserver(), 10000)
  }

  stopDtObserver() {
    this.dtObserver?.disconnect()
    this.dtObserver = null
    clearTimeout(this.dtTimer)
  }

  // ① Open the panel for this table: build the page's panel on first use, then load the editor into its frame
  open(event) {
    event.preventDefault()
    this.lastTrigger = event.currentTarget
    const panel = ensurePanel(PANEL_ID, FRAME_ID, "grid-columns-panel")
    this.startListening(panel)
    this.frame().src = event.currentTarget.href
  }

  startListening(panel) {
    this.stopListening()
    this.panel = panel
    this.onFrameLoad = this.frameLoaded.bind(this)
    this.onHidden = this.panelHidden.bind(this)
    this.frame().addEventListener("turbo:frame-load", this.onFrameLoad)
    panel.addEventListener("hidden.bs.offcanvas", this.onHidden)
    this.onKeydown = bindEscape(() => this.panel)
  }

  stopListening() {
    if (!this.panel) return
    this.frame()?.removeEventListener("turbo:frame-load", this.onFrameLoad)
    this.panel.removeEventListener("hidden.bs.offcanvas", this.onHidden)
    document.removeEventListener("keydown", this.onKeydown)
    this.panel = null
  }

  // The editor arrived (or arrived again with the reasons it was refused), or the save succeeded
  frameLoaded() {
    const saved = this.frame().querySelector("[data-grid-columns-saved]")
    if (saved) {
      this.saved(saved.dataset.label)
    } else {
      window.bootstrap.Offcanvas.getOrCreateInstance(this.panel).show()
    }
  }

  // Empty the frame when the panel closes, so the next table's panel never flashes this one, and give focus back
  panelHidden() {
    const frame = this.frame()
    if (frame) { frame.removeAttribute("src"); frame.innerHTML = "" }
    this.lastTrigger?.focus()
    this.stopListening()
  }

  // ⑥ D9 — reload the table's closest turbo frame from its own URL (search, sort and page kept); a table outside
  // any frame refreshes the page in place
  saved(label) {
    const panel = this.panel
    const tableFrame = this.element.closest("turbo-frame")
    if (panel) window.bootstrap.Offcanvas.getOrCreateInstance(panel).hide()
    if (!tableFrame) { refreshPage(label); return }

    this.element.classList.add("widget-refreshing")
    const done = () => {
      tableFrame.removeEventListener("turbo:frame-load", done)
      // The frame's new content holds a new copy of this wrapper; highlight that one
      const fresh = tableFrame.querySelector("[data-controller~='grid-columns']")
      if (fresh && !prefersReducedMotion()) {
        fresh.classList.add("widget-updated")
        setTimeout(() => fresh.classList.remove("widget-updated"), HIGHLIGHT_MS)
      }
      showToast(label)
    }
    tableFrame.addEventListener("turbo:frame-load", done)
    if (!tableFrame.getAttribute("src")) tableFrame.src = window.location.href
    else tableFrame.reload()
  }

  // D19 — Configure Grids: the editor's frame is in the page; a successful save refreshes the page in place
  listenEmbedded() {
    this.embeddedFrame = this.element.querySelector(`turbo-frame#${FRAME_ID}`)
    if (!this.embeddedFrame) return
    this.onEmbeddedLoad = () => {
      const saved = this.embeddedFrame.querySelector("[data-grid-columns-saved]")
      if (saved) refreshPage(saved.dataset.label)
    }
    this.embeddedFrame.addEventListener("turbo:frame-load", this.onEmbeddedLoad)
  }

  frame() {
    return document.getElementById(FRAME_ID)
  }
}
