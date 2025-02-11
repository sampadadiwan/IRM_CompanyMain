import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["navLink", "tabPane"];

  connect() {
    this.navLinkTargets.forEach(link => {
      link.addEventListener("click", this.switchTab.bind(this));
    });
  }

  switchTab(event) {
    event.preventDefault();

    // Remove active classes from all tabs and panes
    this.navLinkTargets.forEach(link => link.classList.remove("active"));
    this.tabPaneTargets.forEach(tab => {
      tab.classList.remove("active", "show");
      tab.offsetHeight; // Force reflow to ensure proper UI update
    });

    // Activate the clicked tab
    const clickedTab = event.currentTarget;
    clickedTab.classList.add("active");

    // Find the corresponding tab pane
    const targetId = clickedTab.getAttribute("href"); // e.g., #tasks-tab
    const targetPane = this.element.querySelector(targetId);

    if (targetPane) {
      targetPane.offsetHeight; // Force reflow before adding classes
      targetPane.classList.add("active", "show");
    }
  }


}
