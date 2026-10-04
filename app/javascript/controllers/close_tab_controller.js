import { Controller } from "@hotwired/stimulus"

// Closes the current tab - for pages a journey opened in a new window (e.g. the notices-to-approve
// list), once the work there is done. Browsers only allow window.close() on a tab that script
// opened and that has not navigated since, so when the tab is still open a moment later this
// follows the fallback URL (the record's own page) instead; with no fallback it does nothing more.
export default class extends Controller {
  static values = { fallback: String }

  close(event) {
    event.preventDefault()
    window.close()

    // Still here: the browser refused to close it
    setTimeout(() => {
      if (!window.closed && this.fallbackValue) window.location.href = this.fallbackValue
    }, 200)
  }
}
