//import "typeahead"

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sectorField", "primaryEmailField", "primaryEmailEditFlag", "editEmailButton", "editEmailModal"]


connect() {
  console.log("investor_controller connected");
  this.toggleSector()
    // Pre-select category dropdown when default_category URL param is present
    // (used when creating a Portfolio Company from the AI Portfolio Reports form)
    const urlParams = new URLSearchParams(window.location.search);
    console.log("default_category:", urlParams.get('default_category'));
    const defaultCategory = urlParams.get('default_category');
    if (defaultCategory) {
      setTimeout(() => {
        const catSelect = this.element.querySelector('select[name="investor[category]"]');
        if (catSelect) catSelect.value = defaultCategory;
      }, 100);
    }
  }

  toggleSector() {
    const categorySelect = this.element.querySelector("select[name*='category']")
    if (!categorySelect || !this.hasSectorFieldTarget) return

    if (categorySelect.value === "Portfolio Company") {
      this.sectorFieldTarget.style.display = ""
    } else {
      this.sectorFieldTarget.style.display = "none"
    }
}

  close(event) {
    console.log("closeForm");
    $(".dynamic_form").remove();
  }

  // Unlocks the primary_email field client-side AND flips the primary_email_edit
  // hidden field so the form submission carries that intent to the server. Without
  // the hidden field, a server re-render on a validation failure would re-disable
  // the field (its `disabled` state is derived from params[:primary_email_edit]),
  // silently discarding the user's in-progress edit.
  enableEmailEditing() {
    if (this.hasPrimaryEmailFieldTarget) {
      this.primaryEmailFieldTarget.removeAttribute("disabled")
      this.primaryEmailFieldTarget.focus()
    }
    if (this.hasPrimaryEmailEditFlagTarget) {
      this.primaryEmailEditFlagTarget.value = "true"
    }
    if (this.hasEditEmailButtonTarget) {
      this.editEmailButtonTarget.remove()
    }
    if (this.hasEditEmailModalTarget) {
      const modal = bootstrap.Modal.getInstance(this.editEmailModalTarget)
      modal?.hide()
    }
  }
}


