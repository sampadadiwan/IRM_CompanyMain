import { Controller } from "@hotwired/stimulus"

// Documents needing attention: "Check again (n)" shows how many rows are ticked and is disabled at 0.
// openspec/changes/document-checks/design.md (card ⑧ — attention list). Journey J2.3.
export default class extends Controller {
  static targets = ["box", "button"]

  connect() {
    this.changed()
  }

  changed() {
    const count = this.boxTargets.filter((box) => box.checked).length
    this.buttonTarget.disabled = count === 0
    this.buttonTarget.textContent = `Check again (${count})`
  }
}
