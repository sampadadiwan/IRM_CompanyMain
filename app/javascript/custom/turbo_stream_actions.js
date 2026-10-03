import { Turbo } from "@hotwired/turbo-rails"

/**
 * <turbo-stream action="reload_frame" target="frame_id" src="/path"></turbo-stream>
 *
 * Reloads a turbo-frame in place from `src`, as its own user. Broadcast instead of replacing the frame
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
  if (!frame || !src) return

  // Same source: reload (morphs when refresh="morph"). New source: setting it loads it once.
  if (frame.getAttribute("src") === src) {
    frame.reload()
  } else {
    frame.src = src
  }
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
