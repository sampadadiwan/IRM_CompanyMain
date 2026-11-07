import { Controller } from "@hotwired/stimulus"
import { ensurePanel, bindEscape, refreshPage, restoreScroll } from "custom/side_panel"

// ①②⑥ Custom fields in place — openspec/changes/grid-columns-inline-settings (phase 4; D13, D16).
// Sits on a hidden row that display_custom_fields renders among a record's custom field rows: puts the custom
// fields icon on the card holding them, loads the panel into the page's one side panel, and after a save refreshes
// the page in place (the fields are rows of the page's own table, so no frame can reload them alone).
const PANEL_ID = "form_type_fields_panel"
const FRAME_ID = "form_type_fields"

export default class extends Controller {
  static values = { url: String }

  connect() {
    restoreScroll()
    if (document.querySelector(".form-type-fields-btn")) return // one icon per page
    this.button = document.createElement("a")
    this.button.href = this.urlValue
    this.button.title = "Change this record type's custom fields"
    this.button.setAttribute("aria-label", "Change this record type's custom fields")
    this.button.dataset.formTypeFieldsBtn = ""
    this.button.dataset.bsToggle = "tooltip"
    this.button.innerHTML = '<i class="ti ti-forms"></i>'
    this.onOpen = this.open.bind(this)
    this.button.addEventListener("click", this.onOpen)
    this.placeButton()
  }

  // D13 (user, 2026-11-07) — on a form, in the form card's header; on a record's page, beside the minimize button of the collapsible card holding the fields, in its style;
  // else a round button in the breadcrumb bar beside the page's other round buttons; else on the card's corner
  placeButton() {
    // On a form: the form card's header, on its right
    const formHeader = this.element.closest(".form_card")?.querySelector(":scope > .card-header")
    if (formHeader) {
      this.button.className = "btn btn-outline-primary form-type-fields-btn"
      // A flex row so the button sits level with the title (grid_columns.scss .form-type-fields-header)
      formHeader.classList.add("form-type-fields-header")
      formHeader.appendChild(this.button)
      return
    }
    const card = this.element.closest(".card")
    const toggle = card?.querySelector(":scope > .card-header .show_details_link")
    if (toggle) {
      this.button.className = "btn btn-outline-primary me-2 form-type-fields-btn"
      toggle.before(this.button)
      return
    }
    const crumbs = document.querySelector(".breadcrumbs .col-md-2")
    if (crumbs) {
      this.button.className = "fs-5 btn mb-1 btn-primary rounded-circle round d-inline-flex align-items-center justify-content-center ms-1 form-type-fields-btn"
      crumbs.appendChild(this.button)
      return
    }
    const host = card || this.element.closest("table")?.parentElement
    if (!host) return
    host.classList.add("grid-columns-host")
    this.button.className = "grid-columns-btn form-type-fields-btn"
    host.appendChild(this.button)
  }

  disconnect() {
    this.stopListening()
    this.button?.remove()
  }

  open(event) {
    event.preventDefault()
    const panel = ensurePanel(PANEL_ID, FRAME_ID, "form-type-fields-panel")
    this.stopListening()
    this.panel = panel
    this.onFrameLoad = this.frameLoaded.bind(this)
    this.onHidden = this.panelHidden.bind(this)
    this.frame().addEventListener("turbo:frame-load", this.onFrameLoad)
    panel.addEventListener("hidden.bs.offcanvas", this.onHidden)
    this.onKeydown = bindEscape(() => this.panel)
    this.frame().src = this.urlValue
  }

  stopListening() {
    if (!this.panel) return
    this.frame()?.removeEventListener("turbo:frame-load", this.onFrameLoad)
    this.panel.removeEventListener("hidden.bs.offcanvas", this.onHidden)
    document.removeEventListener("keydown", this.onKeydown)
    this.panel = null
  }

  frameLoaded() {
    const saved = this.frame().querySelector("[data-form-type-fields-saved]")
    if (saved) {
      window.bootstrap.Offcanvas.getOrCreateInstance(this.panel).hide()
      refreshPage(saved.dataset.label)
    } else {
      window.bootstrap.Offcanvas.getOrCreateInstance(this.panel).show()
    }
  }

  panelHidden() {
    const frame = this.frame()
    if (frame) { frame.removeAttribute("src"); frame.innerHTML = "" }
    this.button?.focus()
    this.stopListening()
  }

  frame() {
    return document.getElementById(FRAME_ID)
  }
}
