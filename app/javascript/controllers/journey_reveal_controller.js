import { Controller } from "@hotwired/stimulus"

// The breadcrumb's "show the completed journey" icon (layouts/_breadcrumbs).
//
// A journey card (workflow_instances/_journey_panel) hides itself once every task has been done for
// a day or more — a finished checklist shouldn't take up the top of the record's page — but people
// still want to look back at it, so this icon brings it back. A journey that has only just finished
// is still on the page; the icon is there too, and puts it away.
//
// The icon is rendered on every page and hidden; this controller decides whether it belongs on
// THIS page by looking for a completed card, rather than the layout being told by each controller.
// It re-checks on every Turbo frame load because the card is inside a frame that is replaced in
// place when the journey moves on (WorkflowInstancesController#acknowledge, and the real-time
// Workflowable#broadcast_journey_change): ticking off the last task completes the journey there and
// then, and this is what puts the icon in the breadcrumb at that moment rather than after a reload.
//
// Usage:
//   <button data-controller="journey-reveal" data-action="journey-reveal#toggle" class="... d-none">
export default class extends Controller {
  // The events worth re-checking on: the page finishing (the breadcrumb is rendered ABOVE the page
  // body, so at connect time the journey card further down may not be parsed yet), and any frame
  // swap (the journey card's own frame, or any other frame on the page)
  static EVENTS = ["DOMContentLoaded", "turbo:load", "turbo:render", "turbo:frame-load"]

  connect() {
    this.sync = this.sync.bind(this)
    this.constructor.EVENTS.forEach((name) => document.addEventListener(name, this.sync))
    this.sync()
  }

  disconnect() {
    this.constructor.EVENTS.forEach((name) => document.removeEventListener(name, this.sync))
  }

  // Show the icon only while this page has a completed journey card to toggle — hidden (complete
  // for a day or more) or still showing (just finished)
  sync() {
    const complete = this.card !== null
    this.element.classList.toggle("d-none", !complete)
    this.element.classList.toggle("d-inline-flex", complete)
  }

  // Show the card and scroll to it (it sits above the fold but the page may have been scrolled),
  // or put it away again if it is already showing
  toggle() {
    const card = this.card
    if (!card) return

    const hidden = card.classList.contains("d-none")
    card.classList.toggle("d-none", !hidden)
    if (hidden) card.scrollIntoView({ behavior: "smooth", block: "center" })
  }

  // The completed journey card, or null when this page has no journey or it is still in progress
  get card() {
    return document.querySelector("[data-journey-complete='true']")
  }
}
