import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="task-owner"
// This controller is used to manage the visibility of the owner type and owner name fields in the task form
// this changes the form fields on selection from owner Type dropdown
export default class extends Controller {
  static targets = ["ownerType", "ownerForGroup", "ownerForSelect", "ownerNameGroup"]

  connect() {
    this.syncVisibility()
  }

  ownerTypeChanged() {
    this.syncVisibility()
  }

  syncVisibility() {
    if (!this.hasOwnerTypeTarget) return

    const isUserOwner = this.ownerTypeTarget.value === "User"

    if (this.hasOwnerForGroupTarget) {
      this.ownerForGroupTarget.classList.toggle("d-none", isUserOwner)
    }

    if (this.hasOwnerNameGroupTarget) {
      this.ownerNameGroupTarget.classList.toggle("d-none", !isUserOwner)
    }

    if (this.hasOwnerForSelectTarget) {
      const isLocked = this.ownerForSelectTarget.dataset.locked === "true"
      this.ownerForSelectTarget.disabled = isUserOwner || isLocked
    }
  }
}