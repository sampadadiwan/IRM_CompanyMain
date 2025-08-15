import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["pivotCheckbox", "pivotFields", "nonPivotFields"]

  connect() {
    this.toggleFieldsVisibility();
  }

  toggleFieldsVisibility() {
    if (this.pivotCheckboxTarget.checked) {
      console.log("Pivot fields are now visible");
      this.pivotFieldsTarget.classList.remove('d-none');
      this.nonPivotFieldsTarget.classList.add('d-none');
    } else {
      console.log("Non-pivot fields are now visible");
      this.pivotFieldsTarget.classList.add('d-none');
      this.nonPivotFieldsTarget.classList.remove('d-none');
    }
  }
}