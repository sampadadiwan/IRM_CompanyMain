import { Controller } from "@hotwired/stimulus"

// Disables specific buttons (matched by their visible label via data-workflow-gate-label)
// while a workflowable object's current workflow instance is unresolved. Which labels
// get disabled is configured per WorkflowTemplate via its gated_button_labels CSV field —
// admins type labels matching what they see on the button, not DOM ids. This is a JS-only
// UX gate, not a security control: it does not stop a direct request to the underlying action.
//
// Usage:
//   <div data-controller="workflow-gate"
//        data-workflow-gate-labels-value="[&quot;Approve&quot;]"
//        data-workflow-gate-reason-value="Blocked — workflow is Incomplete">
//     <button data-workflow-gate-label="Approve">Approve</button>
//   </div>
export default class extends Controller {
  static values = { labels: Array, reason: String }

  connect() {
    this.labelsValue.forEach((label) => {
      this.element.querySelectorAll(`[data-workflow-gate-label="${CSS.escape(label)}"]`).forEach((el) => {
        this.disable(el)
      })
    })
  }

  disable(el) {
    const reason = this.hasReasonValue && this.reasonValue
      ? this.reasonValue
      : "This action is blocked while a workflow is unresolved."
    el.title = reason
    el.setAttribute("aria-disabled", "true")

    if (el.tagName === "BUTTON" || el.tagName === "INPUT") {
      el.disabled = true
    } else {
      // link_to-rendered buttons have no native disabled state
      el.classList.add("disabled")
      el.style.pointerEvents = "none"
      el.addEventListener("click", (e) => e.preventDefault())
    }
  }
}
