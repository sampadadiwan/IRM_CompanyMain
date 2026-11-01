import { Controller } from "@hotwired/stimulus"

// The report page's Narrow down row: picking a field (or an operator) redraws
// the row with that field's operators and typed input. A plain GET without
// Apply, so nothing is filtered until Apply (report-builder-delivery H10).
export default class extends Controller {
  pick() {
    this.element.requestSubmit()
  }
}
