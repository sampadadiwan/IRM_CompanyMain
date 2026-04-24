import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "input", "results"]

  connect() {
    this.boundKeydown = this.handleKeydown.bind(this)
    window.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    window.removeEventListener("keydown", this.boundKeydown)
  }

  handleKeydown(e) {
    if ((e.metaKey || e.ctrlKey) && e.key === "k") {
      e.preventDefault()
      this.open()
    }
  }

  open() {
    const modal = new bootstrap.Modal(this.modalTarget)
    modal.show()
    setTimeout(() => this.inputTarget.focus(), 500)
  }

  search() {
    const query = this.inputTarget.value.toLowerCase().trim()
    if (query.length < 2) {
      this.resultsTarget.innerHTML = ""
      return
    }

    const items = this.getSearchableItems()
    const filtered = items.filter(item => item.text.includes(query))

    this.renderResults(filtered)
  }

  getSearchableItems() {
    const items = []

    // 1. Available columns from the palette
    document.querySelectorAll("[data-report-builder-target='paletteRow']").forEach(el => {
      items.push({
        text: el.dataset.searchText.toLowerCase(),
        label: el.querySelector("span").textContent,
        type: "Column",
        action: () => el.querySelector("button")?.click()
      })
    })

    // 2. Actions
    items.push({ text: "add formula", label: "Add Formula", type: "Action", action: () => document.querySelector("[data-bs-target='#formulaModal']")?.click() })
    items.push({ text: "templates gallery", label: "Open Templates", type: "Action", action: () => document.querySelector("[data-bs-target='#templateModal']")?.click() })
    items.push({ text: "preview report", label: "Refresh Preview", type: "Action", action: () => document.querySelector("[data-action='click->report-builder#loadPreview']")?.click() })
    items.push({ text: "export xlsx", label: "Export to Excel", type: "Action", action: () => document.querySelector("[data-report-builder-target='exportBtn']")?.click() })

    return items
  }

  renderResults(items) {
    if (items.length === 0) {
      this.resultsTarget.innerHTML = '<div class="p-3 text-center text-muted">No results found.</div>'
      return
    }

    this.resultsTarget.innerHTML = items.map((item, i) => `
      <div class="list-group-item list-group-item-action d-flex align-items-center justify-content-between cursor-pointer" 
           data-action="click->command-palette#execute" data-index="${i}">
        <div>
          <span class="badge bg-light text-muted border me-2">${item.type}</span>
          <span class="fw-bold">${item.label}</span>
        </div>
        <i class="ti ti-chevron-right opacity-50"></i>
      </div>
    `).join("")

    this.currentItems = items
  }

  execute(e) {
    const index = e.currentTarget.dataset.index
    const item = this.currentItems[index]
    if (item && item.action) {
      bootstrap.Modal.getInstance(this.modalTarget).hide()
      item.action()
    }
  }
}
