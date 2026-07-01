import { Controller } from "@hotwired/stimulus"

// Adds/removes nested fields (e.g. workflow_steps) client-side, no server round-trip.
// Cloning replaces the Rails `child_index: "NEW_RECORD"` placeholder with a unique index.
export default class extends Controller {
  static targets = ["target", "template"]
  static values = { wrapperSelector: String }

  add(event) {
    event.preventDefault()

    const newId = new Date().getTime()
    const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, newId)
    this.templateTarget.insertAdjacentHTML("beforebegin", content)
  }

  remove(event) {
    event.preventDefault()

    const wrapper = event.currentTarget.closest(this.wrapperSelectorValue)
    if (!wrapper) return

    // Persisted rows carry a hidden `[id]` field — mark for destruction and hide so
    // accepts_nested_attributes_for still receives id + _destroy=1 on submit.
    // Freshly-added (never-persisted) rows have no id field — just remove them outright.
    const idField = wrapper.querySelector("input[name$='[id]']")
    if (idField && idField.value !== "") {
      wrapper.querySelector(".step-destroy-flag").value = "1"
      wrapper.classList.add("d-none")
    } else {
      wrapper.remove()
    }
  }
}
