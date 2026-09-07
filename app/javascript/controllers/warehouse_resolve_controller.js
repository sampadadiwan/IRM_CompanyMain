// Toggles task-specific fields (due date, assignee) in the warehouse
// resolve form based on the selected intent.
// @see warehouse_items/_resolve_form.html.erb
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["intentSelect", "taskFields"]

  connect() {
    this.toggleTaskFields()
  }

  toggleTaskFields() {
    const isTask = this.intentSelectTarget.value === "task"
    this.taskFieldsTarget.hidden = !isTask
  }
}
