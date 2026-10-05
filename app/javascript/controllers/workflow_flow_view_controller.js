import { Controller } from "@hotwired/stimulus"

// Switches the workflow flow diagram (workflow_templates/_flow_diagram) between
// the vertical "list" spine and the wrapping left-to-right "graph" layout.
// Both layouts share the same markup — the graph is purely the `wffd-graph`
// modifier class on the diagram, restyled in workflow_template.scss.
// The choice is remembered per browser so templates and live runs open the same way.
const STORAGE_KEY = "workflow_flow_view"
const VIEWS = ["list", "graph"]

export default class extends Controller {
  static targets = ["diagram", "button"]

  connect() {
    // Restore the last-used view; storage can throw in private windows, so fall back to list
    let saved = null
    try { saved = localStorage.getItem(STORAGE_KEY) } catch (_e) { /* storage blocked */ }
    this.apply(VIEWS.includes(saved) ? saved : "list")
  }

  // Button click → switch layout and remember it
  switch(event) {
    const view = event.currentTarget.dataset.view
    if (!VIEWS.includes(view)) return

    this.apply(view)
    try { localStorage.setItem(STORAGE_KEY, view) } catch (_e) { /* storage blocked */ }
  }

  apply(view) {
    // Toggle the layout modifier on the diagram (absent when the template has no steps)
    if (this.hasDiagramTarget) {
      this.diagramTarget.classList.toggle("wffd-graph", view === "graph")
    }

    // Reflect the active view on the toggle buttons
    this.buttonTargets.forEach((btn) => {
      const active = btn.dataset.view === view
      btn.classList.toggle("active", active)
      btn.setAttribute("aria-pressed", active)
    })
  }
}
