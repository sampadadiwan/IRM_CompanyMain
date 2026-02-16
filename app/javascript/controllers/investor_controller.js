//import "typeahead"

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sectorField"]


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
}


