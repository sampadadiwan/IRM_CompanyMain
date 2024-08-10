import { Controller } from "@hotwired/stimulus";

export default class GridViewController extends Controller {
  static targets = ["select", "form"]

  connect() {
    this.selectTarget.addEventListener("change", this.submitForm.bind(this));
  }

  submitForm() {
    this.formTarget.requestSubmit();
  }
}
