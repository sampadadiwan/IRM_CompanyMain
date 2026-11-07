import { Controller } from "@hotwired/stimulus"
import { bindEscape, showToast, refreshPage, restoreScroll, prefersReducedMotion } from "custom/side_panel"

// Widget settings in place — openspec/changes/archive/2026-11-07-dashboard-widget-inline-settings (cards ②, ⑥, ⑦; D4, D5, D7).
// Sits on a dashboard's widget row. The settings icon loads the form into the popup's frame; this controller
// opens the panel when the form arrives, and when the save answers with the saved marker it closes the panel and
// reloads only that widget (or the whole page after the dashboard's defaults were saved).
// Toast, Esc, page refresh and reduced motion are shared with the table columns and custom fields panels
// (custom/side_panel.js — openspec/changes/grid-columns-inline-settings D12)
const FRAME_ID = "widget_settings"
const HIGHLIGHT_MS = 1200

export default class extends Controller {
  static targets = ["modal"]

  connect() {
    this.onFrameLoad = this.frameLoaded.bind(this)
    document.addEventListener("turbo:frame-load", this.onFrameLoad)
    // Esc closes the panel wherever keyboard focus is (Bootstrap's own Esc only works with focus inside it)
    this.onKeydown = bindEscape(() => (this.hasModalTarget ? this.modalTarget : null))
    // D5 — after a full refresh, put the page back where it was
    restoreScroll()
    if (this.hasModalTarget) {
      // Empty the frame when the panel closes, so the next widget's panel never flashes the previous form,
      // and give keyboard focus back to the icon that opened it
      this.modalTarget.addEventListener("hidden.bs.offcanvas", () => {
        const frame = this.frame()
        if (frame) { frame.removeAttribute("src"); frame.innerHTML = "" }
        this.lastTrigger?.focus()
      })
    }
  }

  disconnect() {
    document.removeEventListener("turbo:frame-load", this.onFrameLoad)
    document.removeEventListener("keydown", this.onKeydown)
  }

  // ① Remember which icon opened the popup (focus returns there)
  opening(event) {
    this.lastTrigger = event.currentTarget
  }

  // ③ Save and refresh: spinner on, button off until the answer arrives (double clicks send one save)
  submitting(event) {
    const button = event.target.querySelector("[data-widget-settings-target='submit']")
    const spinner = event.target.querySelector("[data-widget-settings-target='spinner']")
    const icon = event.target.querySelector("[data-widget-settings-target='saveIcon']")
    if (button) button.disabled = true
    if (spinner) spinner.classList.remove("d-none")
    if (icon) icon.classList.add("d-none")
  }

  frameLoaded(event) {
    const frame = event.target
    if (frame.id !== FRAME_ID || !this.element.contains(frame)) return

    const saved = frame.querySelector("[data-widget-settings-saved]")
    if (saved) {
      this.saved(saved.dataset)
    } else {
      // The form (or the form again with the reasons it was refused): show the panel
      this.modal().show()
    }
  }

  // ④ → ⑥ The save succeeded
  saved({ key, refresh, sizeClass, label }) {
    this.modal().hide()
    const container = document.getElementById(key)
    const widgetFrame = document.getElementById(`dashboard_widget_${key}`)
    if (refresh === "page" || !container || !widgetFrame) {
      this.refreshPage()
      return
    }
    this.reloadWidget(container, widgetFrame, sizeClass, label)
  }

  // D4 — reload one widget through the dashboard's own URL, so the page rebuilds its context (fund, company, filters)
  reloadWidget(container, widgetFrame, sizeClass, label) {
    container.classList.add("widget-refreshing")
    const url = new URL(this.dashboardUrl())
    url.searchParams.set("only_widget", container.id)

    const done = (ok) => {
      container.classList.remove("widget-refreshing")
      widgetFrame.removeEventListener("turbo:frame-load", onLoad)
      widgetFrame.removeEventListener("turbo:fetch-request-error", onError)
      if (!ok) {
        widgetFrame.innerHTML = '<p class="text-muted text-center py-3 mb-0">Could not refresh — reload the page.</p>'
        return
      }
      // E8 / changed layout — an empty answer means the widget is no longer there: refresh the whole page
      if (widgetFrame.children.length === 0) { this.refreshPage(); return }
      // H4 — a new size takes effect in the same refresh
      if (sizeClass) this.swapSizeClass(container, sizeClass)
      this.highlight(container)
      this.toast(label)
    }
    const onLoad = () => done(true)
    const onError = () => done(false)
    widgetFrame.addEventListener("turbo:frame-load", onLoad)
    widgetFrame.addEventListener("turbo:fetch-request-error", onError)
    widgetFrame.src = url.toString()
  }

  // D5 — after saving the defaults every widget's key changes: refresh the page in place, keeping the scroll.
  // A dashboard loaded into a frame (the fund page's Portfolio Dashboard tab) reloads just that frame, so the
  // page keeps its open tab; restoreScroll runs again when this controller reconnects on the new content.
  refreshPage() {
    const frame = this.dashboardFrame()
    if (frame) {
      refreshPage(null, frame)
    } else {
      refreshPage()
    }
  }

  // The frame the dashboard was loaded into from its own URL (e.g. funds/_owner_fund_details'
  // portfolio_dashboard_frame → /funds/:id/dashboard?dashboard_name=Portfolio+Dashboard), or null when the
  // dashboard is the page itself. Searched from above the widget row, so a widget's own frame (which gets a src
  // after its first reload) and the settings panel's frame never match.
  dashboardFrame() {
    return this.element.parentElement?.closest("turbo-frame[src]") || null
  }

  // The URL that draws this dashboard: the browser's URL only when the dashboard is the page itself — a frame's
  // host page (/funds/:id) has no widget frames, so asking it for ?only_widget= answered "This section couldn't load"
  dashboardUrl() {
    const frame = this.dashboardFrame()
    // A frame's src may be relative; resolve it against the page
    return frame ? new URL(frame.getAttribute("src"), window.location.href).toString() : window.location.href
  }

  swapSizeClass(container, sizeClass) {
    container.classList.forEach((cls) => { if (/^col(-md-\d+)?$/.test(cls)) container.classList.remove(cls) })
    container.classList.add(sizeClass)
  }

  // ⑦ A short highlight ring; skipped when the user asks for reduced motion (E7)
  highlight(container) {
    if (this.reducedMotion()) return
    container.classList.add("widget-updated")
    setTimeout(() => container.classList.remove("widget-updated"), HIGHLIGHT_MS)
  }

  // ⑦ "<widget> updated", bottom-right, for a few seconds
  toast(label) {
    showToast(label)
  }

  // ② The settings panel (a Bootstrap offcanvas sliding in from the right)
  modal() {
    return window.bootstrap.Offcanvas.getOrCreateInstance(this.modalTarget)
  }

  frame() {
    return this.element.querySelector(`turbo-frame#${FRAME_ID}`)
  }

  reducedMotion() {
    return prefersReducedMotion()
  }
}
