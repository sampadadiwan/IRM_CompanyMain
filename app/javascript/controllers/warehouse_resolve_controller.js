// Toggles task-specific fields (due date, assignee) in the warehouse
// resolve form based on the selected intent.
// Removes/adds hidden attribute and sets display style to ensure
// Bootstrap flex classes don't interfere with visibility.
// @see warehouse_items/_resolve_form.html.erb
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["intentSelect", "taskFields"]

  connect() {
    this.toggleTaskFields()
  }

  toggleTaskFields() {
    const isTask = this.intentSelectTarget.value === "task"
    if (isTask) {
      this.taskFieldsTarget.removeAttribute("hidden")
      this.taskFieldsTarget.style.display = "block"
    } else {
      this.taskFieldsTarget.setAttribute("hidden", "")
      this.taskFieldsTarget.style.display = "none"
    }
  }
}
