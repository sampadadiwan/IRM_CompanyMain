import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  toggleAllDetails(event) {
    event.preventDefault();

    // Get the collapse element within this form
    const collapse = this.element.closest("form").querySelector(".collapse");
    if (!collapse) return;

    // Toggle the show class
    collapse.classList.toggle("show");

    // Update the button icon
    const icon = this.element.querySelector("i");
    if (icon) {
      if (collapse.classList.contains("show")) {
        // Expanded - show up caret
        icon.className = "ti ti-caret-up";
      } else {
        // Collapsed - show down caret
        icon.className = "ti ti-caret-down";
      }
    }
  }
}
