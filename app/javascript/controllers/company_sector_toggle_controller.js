import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="company-sector-toggle"
// Makes the side by side company and sector others lists toggleable and maintains same size
export default class extends Controller {
  connect() {
    this.element.querySelectorAll('[data-role="company-others-toggle"]').forEach(btn => {
      btn.onclick = () => {
        const icon = btn.querySelector('[data-role="company-others-toggle-icon"]')
        if (icon) icon.textContent = icon.textContent === "▸" ? "▾" : "▸"

        const summaryRow = btn.closest('tr')
        const listRow = summaryRow.nextElementSibling
        if (listRow && listRow.dataset.role === "company-others-list-row") {
          listRow.classList.toggle("d-none")
        }
      }
    })

    this.element.querySelectorAll('[data-role="sector-others-toggle"]').forEach(btn => {
      btn.onclick = () => {
        const icon = btn.querySelector('[data-role="sector-others-toggle-icon"]')
        if (icon) icon.textContent = icon.textContent === "▸" ? "▾" : "▸"

        const summaryRow = btn.closest('tr')
        const listRow = summaryRow.nextElementSibling
        if (listRow && listRow.dataset.role === "sector-others-list-row") {
          listRow.classList.toggle("d-none")
        }
      }
    })
  }
}
