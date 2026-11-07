import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="company-sector-toggle"
// Expands / collapses the "Other" row of the company and sector tables: the items folded into Other are
// ordinary hidden rows right after it, each with data-role="<kind>-others-list-row".
export default class extends Controller {
  connect() {
    ["company", "sector"].forEach(kind => {
      this.element.querySelectorAll(`[data-role="${kind}-others-toggle"]`).forEach(btn => {
        btn.onclick = () => {
          // Flip the arrow
          const icon = btn.querySelector(`[data-role="${kind}-others-toggle-icon"]`)
          if (icon) icon.textContent = icon.textContent === "▸" ? "▾" : "▸"
          btn.setAttribute("aria-expanded", btn.getAttribute("aria-expanded") === "true" ? "false" : "true")

          // Show / hide every list row that follows the Other row
          let row = btn.closest("tr").nextElementSibling
          while (row && row.dataset.role === `${kind}-others-list-row`) {
            row.classList.toggle("d-none")
            row = row.nextElementSibling
          }
        }
      })
    })
  }
}
