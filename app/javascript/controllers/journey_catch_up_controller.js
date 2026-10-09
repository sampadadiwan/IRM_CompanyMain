import { Controller } from "@hotwired/stimulus"

// Catches a record's journey panel up each time its real-time subscription comes up, so a journey
// change broadcast while nobody was listening is not lost (workflow_instances/_journey_stream).
//
// Workflowable#broadcast_journey_change only reaches pages already subscribed when it fires. A button
// that queues a job and redirects (e.g. the KPI report's "Send upload request") reloads the whole
// page: the old page's subscription closes, the new page renders the journey as it was, and the job
// can finish and broadcast before the new page's WebSocket has subscribed — the update is dropped and
// the panel stays a step behind until the next reload. A dropped connection has the same gap.
//
// Turbo sets the `connected` attribute on <turbo-cable-stream-source> when its subscription is
// confirmed (and removes it on disconnect); this controller sits on that element and, on every
// transition to connected, fetches a fresh panel in the background and compares its fingerprint
// (data-journey-version, JourneyHelper#journey_version) with the one on the page. Only when they
// differ is the panel swapped in. Swapping an unchanged panel would replace its buttons under a
// click that is already on its way — the click then lands on a detached element and is lost.
//
// Usage (rendered by workflow_instances/_journey_stream):
//   <turbo-cable-stream-source data-controller="journey-catch-up"
//     data-journey-catch-up-frame-value="kpi_report_journey"
//     data-journey-catch-up-src-value="/kpi_reports/2752/journey" ...>
export default class extends Controller {
  static values = { frame: String, src: String }

  connect() {
    // Watch the stream source's own `connected` attribute; it may already be set if the
    // subscription was confirmed before Stimulus attached
    this.wasConnected = false
    this.observer = new MutationObserver(() => this.sync())
    this.observer.observe(this.element, { attributes: true, attributeFilter: ["connected"] })
    this.sync()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  // Check on each disconnected → connected transition only, not on every attribute write
  sync() {
    const connected = this.element.hasAttribute("connected")
    if (connected && !this.wasConnected) this.catchUp()
    this.wasConnected = connected
  }

  // Fetch the panel without touching the page; swap it in only if the journey moved on meanwhile
  async catchUp() {
    const frame = document.getElementById(this.frameValue)
    if (!frame || !this.srcValue) return

    try {
      const response = await fetch(this.srcValue, {
        headers: { Accept: "text/html", "Turbo-Frame": this.frameValue },
        credentials: "same-origin"
      })
      if (!response.ok) return

      // Compare the fresh panel's fingerprint with the one currently on the page
      const fresh = new DOMParser().parseFromString(await response.text(), "text/html")
      if (this.versionIn(fresh) === this.versionIn(frame)) return

      // The journey changed: load the panel through Turbo so it fires turbo:frame-load (tooltips,
      // journey-reveal), exactly as a broadcast does
      if (frame.getAttribute("src") === this.srcValue) {
        frame.reload()
      } else {
        frame.src = this.srcValue
      }
    } catch (error) {
      // A failed catch-up leaves the panel as rendered; the next broadcast or reload corrects it
      console.warn("journey-catch-up: could not check the journey panel", error)
    }
  }

  // The data-journey-version inside a panel (a parsed response or the live frame)
  versionIn(root) {
    return root.querySelector("[data-journey-version]")?.getAttribute("data-journey-version")
  }
}
