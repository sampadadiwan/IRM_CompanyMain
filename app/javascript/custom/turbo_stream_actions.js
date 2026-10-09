import { Turbo } from "@hotwired/turbo-rails"

/**
 * <turbo-stream action="reload_frame" target="frame_id" src="/path"></turbo-stream>
 *
 * Reloads a turbo-frame in place from `src`, as its own user. `src` is optional: without it the frame
 * reloads from its current src (so a filter the user applied to it survives). Broadcast instead of replacing the frame
 * with an empty <turbo-frame src>: that blanked the frame until the fetch returned, so the page lost its
 * height and jumped (the Document checks tab did this after every document checked).
 *
 * The old content stays on screen until the new content arrives. A frame marked refresh="morph" is
 * morphed on reload (only what changed is patched), so the page keeps its scroll position. Morphing
 * would still close an open <details> and clear typed text (the server's HTML has neither); the two
 * listeners below keep what the user is in the middle of.
 * See DocChecks::Broadcast (app/packs/core/documents/services/doc_checks/broadcast.rb).
 */
Turbo.StreamActions.reload_frame = function () {
  // Each step: find the frame on this page, if it is showing
  const frame = document.getElementById(this.target)
  const src = this.getAttribute("src")
  if (!frame) return

  // No src: reload whatever the frame is showing now, keeping any filter the user applied to it
  // (the capital call's remittances list — CapitalCall#broadcast_remittances_change)
  if (!src) {
    if (frame.getAttribute("src")) reloadWhenIdle(frame)
    return
  }

  // Same source: reload (morphs when refresh="morph"). New source: setting it loads it once.
  if (frame.getAttribute("src") === src) {
    reloadWhenIdle(frame)
  } else {
    frame.src = src
  }
}

/**
 * frame.reload(), but never while a load is in flight. Reloading cancels the in-flight request, and when that
 * request is a lazy frame's first load Turbo (8.0.x FrameController) never starts another: it only reloads a
 * lazy frame on a src change once #hasBeenLoaded, which the cancelled load never sets. The frame then keeps
 * its loading spinner for good — e.g. a call page opened while CapitalCallJob runs, whose first remittances
 * fetch is cut off by the job's next reload_frame.
 * So a busy frame is reloaded once a load has finished; a burst of broadcasts meanwhile becomes one reload
 * (the reload fetches the latest state anyway).
 * Waits on events rather than frame.loaded: that promise never settles if its load is cancelled (e.g. the
 * user picks a remittances filter, which sets a new src), and the queued reload would then never run.
 */
function reloadWhenIdle(frame) {
  // Idle: reload now (cancels nothing)
  if (!frame.hasAttribute("busy")) {
    frame.reload()
    return
  }

  // Busy: one queued reload per frame
  if (frame.reloadQueued) return
  frame.reloadQueued = true

  // Whichever load finishes next — rendered (turbo:frame-load) or failed at the network (turbo:fetch-request-error)
  const done = () => {
    frame.removeEventListener("turbo:frame-load", done)
    frame.removeEventListener("turbo:fetch-request-error", done)
    // Next task, not now: both events fire before Turbo has finished with the load — the error one while the
    // frame is still busy, and frame-load before Turbo marks the frame as loaded (#hasBeenLoaded), so
    // reloading inside the event would hit the same stuck-spinner case
    setTimeout(() => {
      frame.reloadQueued = false
      // The frame may have left the page (navigation) while it was loading
      if (frame.isConnected) reloadWhenIdle(frame)
    }, 0)
  }
  frame.addEventListener("turbo:frame-load", done)
  frame.addEventListener("turbo:fetch-request-error", done)
}

// Inside a morphing frame, keep a <details> the user opened (e.g. the "Keep the KYC's …" reason box)
document.addEventListener("turbo:before-morph-attribute", (event) => {
  const el = event.target
  if (event.detail.attributeName === "open" && el.tagName === "DETAILS" && el.closest('turbo-frame[refresh="morph"]')) {
    event.preventDefault()
  }
})

// …and leave alone a text field being typed in, or holding typed text. Only when the field is still in the
// new HTML (no newElement means it is being removed: let it go)
document.addEventListener("turbo:before-morph-element", (event) => {
  const el = event.target
  if (!event.detail.newElement || !el.matches?.("input:not([type=hidden]), textarea")) return
  if (!el.closest('turbo-frame[refresh="morph"]')) return

  if (el === document.activeElement || el.value !== el.defaultValue) event.preventDefault()
})
