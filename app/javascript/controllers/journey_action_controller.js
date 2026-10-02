import { Controller } from "@hotwired/stimulus"

// The journey panel's action button, when the task's real control is already on this page.
//
// Worked examples H18 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
//
// The panel sits on the capital call page, so a link to the call just reloads it. Instead the
// check names the control that does the work (data-journey-action-control-value): a button's DOM
// id ("capital_call_approve_btn"), or "#some-tab" for a tab to open. We click THAT control so its
// own confirm popup, rule-validation modal and workflow gate all run exactly as if the user had
// found it themselves — nothing is duplicated here.
//
// The link keeps its href as the fallback: if the control isn't on the page (the user's policy
// doesn't render it, or the panel is shown somewhere else), we don't preventDefault and the
// browser navigates as before.
//
// Usage:
//   <a href="/capital_calls/1" data-controller="journey-action"
//      data-journey-action-control-value="capital_call_notify_btn"
//      data-action="click->journey-action#run">Send Notification</a>
export default class extends Controller {
  static values = { control: String }

  run(event) {
    const control = this.findControl()
    if (!control) return // no such control here — let the href do what it has always done

    event.preventDefault()

    // A workflow-gated button is natively disabled, so clicking it would do nothing at all and
    // leave the user wondering. Show them the button and why it is blocked instead.
    if (control.disabled || control.getAttribute("aria-disabled") === "true") {
      this.reveal(control)
      this.explain(control)
      return
    }

    this.reveal(control)
    control.click()
  }

  // The control this action drives: a tab ("#id") to open, or a button by its id
  findControl() {
    if (!this.hasControlValue) return null
    if (this.controlValue.startsWith("#")) return document.querySelector(`[href="${this.controlValue}"]`)

    return document.getElementById(this.controlValue)
  }

  // Bring the control into view: open the dropdown holding it (a click on a hidden button still
  // submits, but the user should see what they just set off), then scroll and flash it.
  reveal(control) {
    const menu = control.closest(".dropdown-menu")
    const toggle = menu?.parentElement?.querySelector("[data-bs-toggle='dropdown']")
    if (toggle && !menu.classList.contains("show")) {
      window.bootstrap?.Dropdown?.getOrCreateInstance(toggle)?.show()
    }

    control.scrollIntoView({ behavior: "smooth", block: "center" })
    control.classList.add("journey-action-flash")
    setTimeout(() => control.classList.remove("journey-action-flash"), 1600)
  }

  // Say why a blocked control can't be used, borrowing the reason the gate already put on it
  explain(control) {
    const reason = control.title || "This action is not available yet."
    const Tooltip = window.bootstrap?.Tooltip
    if (!Tooltip) return

    const tip = Tooltip.getOrCreateInstance(control, { title: reason, trigger: "manual" })
    tip.show()
    setTimeout(() => tip.hide(), 3000)
  }
}
