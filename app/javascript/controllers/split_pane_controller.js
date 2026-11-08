import { Controller } from "@hotwired/stimulus"

// Two side-by-side panes (e.g. the folder tree | document list on documents/_tree_view) with a draggable
// divider between them. Only the LEFT pane's width is set (as a % of the row, in --split-pane-left-width);
// the right pane flexes into the rest (custom/split_pane.scss). Below the lg breakpoint the CSS ignores the
// variable and the divider is hidden, so the panes stack exactly as before.
//   drag the divider      -> resize, saved per browser under storageKey when the drag ends
//   ← / → on the divider  -> resize by `step` px
//   double-click          -> back to the default split (Bootstrap's col-lg-4) and forget the saved width
export default class extends Controller {
  static targets = ["left", "divider"]
  static values = {
    storageKey: String,
    min: { type: Number, default: 220 },        // narrowest the left pane may go, px
    maxFraction: { type: Number, default: 0.6 }, // widest the left pane may go, share of the row
    step: { type: Number, default: 16 }          // keyboard nudge, px
  }

  connect() {
    // Bound once so the same function can be added and removed as a listener
    this.onPointerMove = this.onPointerMove.bind(this)
    this.onPointerUp = this.onPointerUp.bind(this)

    // Restore the width this browser last used; nothing saved = keep the col-lg-4 default
    const saved = this.readSaved()
    if (saved) this.applyFraction(saved)
    this.updateAria()
  }

  disconnect() {
    this.stopDrag()
  }

  // pointerdown on the divider: capture the pointer so moves keep arriving even off the divider
  startDrag(event) {
    if (event.button !== 0) return
    event.preventDefault()
    this.hideTooltip()
    this.dividerTarget.setPointerCapture(event.pointerId)
    this.element.classList.add("split-pane--dragging")
    this.dividerTarget.addEventListener("pointermove", this.onPointerMove)
    this.dividerTarget.addEventListener("pointerup", this.onPointerUp)
    this.dividerTarget.addEventListener("pointercancel", this.onPointerUp)
  }

  // The left pane's new width is the pointer's distance from the pane's own left edge
  onPointerMove(event) {
    const leftEdge = this.leftTarget.getBoundingClientRect().left
    this.applyFraction((event.clientX - leftEdge) / this.rowWidth())
  }

  // Drag finished: stop listening and remember the width
  onPointerUp() {
    this.stopDrag()
    this.save()
  }

  stopDrag() {
    if (!this.hasDividerTarget) return
    this.element.classList.remove("split-pane--dragging")
    this.dividerTarget.removeEventListener("pointermove", this.onPointerMove)
    this.dividerTarget.removeEventListener("pointerup", this.onPointerUp)
    this.dividerTarget.removeEventListener("pointercancel", this.onPointerUp)
  }

  // ← / → while the divider has focus
  nudge(event) {
    const direction = { ArrowLeft: -1, ArrowRight: 1 }[event.key]
    if (!direction) return
    event.preventDefault()
    this.applyFraction(this.currentFraction() + (direction * this.stepValue) / this.rowWidth())
    this.save()
  }

  // Double-click: drop the custom width so the Bootstrap default applies again
  reset() {
    this.fraction = null
    this.element.style.removeProperty("--split-pane-left-width")
    this.forget()
    this.updateAria()
  }

  // Window resized: re-clamp, since the px minimum is a bigger share of a narrower row
  refit() {
    if (this.fraction) this.applyFraction(this.fraction)
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  applyFraction(fraction) {
    this.fraction = this.clamp(fraction)
    this.element.style.setProperty("--split-pane-left-width", `${(this.fraction * 100).toFixed(3)}%`)
    this.updateAria()
  }

  // Keep the left pane between `min` px and `maxFraction` of the row
  clamp(fraction) {
    const minFraction = Math.min(this.minValue / this.rowWidth(), this.maxFractionValue)
    return Math.min(Math.max(fraction, minFraction), this.maxFractionValue)
  }

  // The width in force now: the custom one, or whatever the default column renders at
  currentFraction() {
    return this.fraction || this.leftTarget.getBoundingClientRect().width / this.rowWidth()
  }

  rowWidth() {
    return this.element.getBoundingClientRect().width || 1
  }

  // Screen readers announce the divider's position as a percentage of the row
  updateAria() {
    if (!this.hasDividerTarget) return
    this.dividerTarget.setAttribute("aria-valuemin", Math.round(this.clamp(0) * 100))
    this.dividerTarget.setAttribute("aria-valuemax", Math.round(this.maxFractionValue * 100))
    this.dividerTarget.setAttribute("aria-valuenow", Math.round(this.currentFraction() * 100))
  }

  // The divider has a Bootstrap tooltip ("Drag to resize…"); don't let it hang over the drag
  hideTooltip() {
    window.bootstrap?.Tooltip?.getInstance(this.dividerTarget)?.hide()
  }

  // localStorage can be missing or throw (private window, blocked site data): fall back to the default split
  readSaved() {
    if (!this.storageKeyValue) return null
    try {
      const value = parseFloat(window.localStorage.getItem(this.storageKeyValue))
      return value > 0 && value < 1 ? value : null
    } catch (_e) {
      return null
    }
  }

  save() {
    if (!this.storageKeyValue || !this.fraction) return
    try { window.localStorage.setItem(this.storageKeyValue, this.fraction.toFixed(4)) } catch (_e) { /* not saved; fine */ }
  }

  forget() {
    if (!this.storageKeyValue) return
    try { window.localStorage.removeItem(this.storageKeyValue) } catch (_e) { /* nothing to forget */ }
  }
}
