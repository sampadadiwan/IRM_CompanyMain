// Shared pieces of the in-place side panels: dashboard widget settings, table columns and record custom fields.
// openspec/changes/grid-columns-inline-settings — design D8, D12, D16 (extracted from widget_settings_controller.js,
// openspec/changes/archive/2026-11-07-dashboard-widget-inline-settings — D5, D7)

const TOAST_MS = 3000
const SCROLL_KEY = "sidePanelScrollY"
const TOAST_KEY = "sidePanelToast"

// The user asked their system for less motion (E7 of the widget change; same rule for every panel)
export function prefersReducedMotion() {
  return !!(window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches)
}

// D8 — one offcanvas per page holding a turbo frame, created on first use and reused afterwards. Turbo Drive
// replaces <body> on navigation, so the next page starts without it. Returns the panel element.
export function ensurePanel(panelId, frameId, extraClass) {
  let panel = document.getElementById(panelId)
  if (panel) return panel

  panel = document.createElement("div")
  panel.id = panelId
  panel.className = `offcanvas offcanvas-end widget-settings-panel ${extraClass || ""}`.trim()
  panel.tabIndex = -1
  panel.setAttribute("aria-labelledby", `${frameId}_title`)
  const frame = document.createElement("turbo-frame")
  frame.id = frameId
  frame.className = "widget-settings-frame"
  panel.appendChild(frame)
  document.body.appendChild(panel)
  return panel
}

// Esc closes an open panel wherever keyboard focus is (Bootstrap's own Esc only works with focus inside it).
// Returns the listener so the caller can remove it on disconnect.
export function bindEscape(getPanel) {
  const listener = (event) => {
    const panel = getPanel()
    if (event.key === "Escape" && panel && panel.classList.contains("show")) {
      window.bootstrap.Offcanvas.getOrCreateInstance(panel).hide()
    }
  }
  document.addEventListener("keydown", listener)
  return listener
}

// "<thing> saved", bottom-right, for a few seconds
export function showToast(label) {
  let area = document.querySelector(".widget-settings-toast-area")
  if (!area) {
    area = document.createElement("div")
    area.className = "widget-settings-toast-area"
    document.body.appendChild(area)
  }
  const toast = document.createElement("div")
  toast.className = "toast widget-settings-toast align-items-center"
  toast.setAttribute("role", "status")
  toast.setAttribute("aria-live", "polite")
  toast.dataset.widgetSettingsToast = ""
  const body = document.createElement("div")
  body.className = "toast-body d-flex align-items-center gap-2"
  body.innerHTML = '<i class="ti ti-circle-check text-success fs-5"></i>'
  body.appendChild(document.createTextNode(label || "Saved"))
  toast.appendChild(body)
  area.appendChild(toast)
  const instance = window.bootstrap.Toast.getOrCreateInstance(toast, { delay: TOAST_MS, animation: !prefersReducedMotion() })
  toast.addEventListener("hidden.bs.toast", () => toast.remove())
  instance.show()
}

// D16 — refresh the page in place, keeping the scroll position (restored by restoreScroll on the next load);
// a toast label given here is shown once the page is back. Given a frame that was loaded from its own src,
// only that frame is reloaded — its host page could not redraw the frame's content.
export function refreshPage(toastLabel, frame) {
  sessionStorage.setItem(SCROLL_KEY, String(window.scrollY))
  if (toastLabel) sessionStorage.setItem(TOAST_KEY, toastLabel)
  if (frame) {
    frame.reload()
  } else {
    window.Turbo.visit(window.location.href, { action: "replace" })
  }
}

// Put the page back where it was after refreshPage, and show its toast; call from a controller's connect()
export function restoreScroll() {
  const savedScroll = sessionStorage.getItem(SCROLL_KEY)
  if (savedScroll !== null) {
    sessionStorage.removeItem(SCROLL_KEY)
    window.scrollTo(0, parseInt(savedScroll, 10))
  }
  const toastLabel = sessionStorage.getItem(TOAST_KEY)
  if (toastLabel !== null) {
    sessionStorage.removeItem(TOAST_KEY)
    showToast(toastLabel)
  }
}

// Spinner on, button off while a panel form saves (double clicks send one save — E6, E22)
export function markSaving(form) {
  const button = form.querySelector("[type='submit']")
  const spinner = form.querySelector("[data-side-panel-spinner]")
  const icon = form.querySelector("[data-side-panel-save-icon]")
  if (button) button.disabled = true
  if (spinner) spinner.classList.remove("d-none")
  if (icon) icon.classList.add("d-none")
}
