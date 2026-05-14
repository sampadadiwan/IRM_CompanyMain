import { Controller } from "@hotwired/stimulus"

// Shows/hides validation rule inputs in the form type setup page based on the
// selected field type. Each nested field row has its own instance of this controller.
export default class extends Controller {
  static targets = ["fieldType"]

  connect() {
    this.applyRules()
  }

  fieldTypeChanged() {
    this.applyRules()
  }

  applyRules() {
    const fieldType = this.fieldTypeTarget.value.toLowerCase()

    // Any div with a fcf-vr-* class is type-specific.
    // Show it only if one of its fcf-vr-* classes matches the current field type.
    // Divs with no fcf-vr-* class (Unique, Custom Error Message) are always visible.
    this.element.querySelectorAll("[class*='fcf-vr-']").forEach(group => {
      const vrClasses = Array.from(group.classList).filter(c => c.startsWith("fcf-vr-"))
      const visible = vrClasses.some(c => c === `fcf-vr-${fieldType}`)
      group.style.display = visible ? "" : "none"
    })
  }
}
