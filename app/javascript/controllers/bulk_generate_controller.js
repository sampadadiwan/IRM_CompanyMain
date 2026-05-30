import { Controller } from "@hotwired/stimulus"

// Drives the bulk-generate form: select all / clear all portfolio company checkboxes.
export default class extends Controller {
  static targets = ["companyList"]

  selectAll() {
    this.companyListTarget.querySelectorAll(".pc-checkbox").forEach(cb => cb.checked = true)
  }

  clearAll() {
    this.companyListTarget.querySelectorAll(".pc-checkbox").forEach(cb => cb.checked = false)
  }
}
