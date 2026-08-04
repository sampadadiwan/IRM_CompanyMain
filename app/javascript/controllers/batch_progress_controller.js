import { Controller } from "@hotwired/stimulus"

/**
 * Watches batch progress broadcasts and auto-reloads the active reports tab
 * when a batch run completes. Connected via data-controller="batch-progress"
 * on the _batch_progress_panel partial.
 */
export default class extends Controller {
  static values = {
    supportAgentId: Number,
    status: String
  }

  /** @param {string} newStatus — triggered by Turbo Stream replacing the panel */
  statusValueChanged(newStatus) {
    if (newStatus === "complete") {
      if (this.isDashboardPage()) {
        setTimeout(() => window.location.reload(), 1500)
      } else {
        this.reloadReportsTab()
      }
    }
  }

  isDashboardPage() {
    return window.location.pathname.includes("portfolio_company_dashboard")
  }

  /** Fetches the current page with the active tab param and swaps in fresh content */
  reloadReportsTab() {
    const tabContent = document.querySelector(".tab-pane.show.active")
    if (!tabContent) return

    const tabId = tabContent.id
    if (tabId === "general-tab") return

    const tabLink = document.querySelector(`a[href="#${tabId}"]`)
    if (!tabLink) return

    const url = new URL(window.location.href)
    url.searchParams.set("tab", tabId.replace("-tab", "").replace(/-/g, "_"))

    fetch(url.toString(), {
      headers: {
        "Accept": "text/html",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      }
    })
      .then(response => response.text())
      .then(html => {
        const parser = new DOMParser()
        const doc = parser.parseFromString(html, "text/html")
        const newContent = doc.getElementById(tabId)
        if (newContent) {
          tabContent.innerHTML = newContent.innerHTML
        }
      })
      .catch(error => console.error("Batch progress: tab reload failed", error))
  }
}
