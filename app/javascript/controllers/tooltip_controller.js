import { Controller } from "@hotwired/stimulus";
import * as bootstrap from "bootstrap";

export default class extends Controller {
  connect() {
    const tooltipElements = this.element.querySelectorAll("[data-toggle='tooltip']");
    tooltipElements.forEach((element) => {
      new bootstrap.Tooltip(element);
    });
  }
}
