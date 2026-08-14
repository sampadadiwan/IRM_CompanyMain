import { Controller } from "@hotwired/stimulus"

// Sector / tag scope selectors on the Portfolio Scoring Dashboard.
//
// Each option's value is the full URL for that scope, built server-side with the
// other active filters already merged in. Selecting one is therefore a plain
// navigation — no form, no query-string assembly in the browser, and no way for
// the client and server to disagree about which filters are in force.
export default class extends Controller {
  navigate(event) {
    const url = event.target.value
    if (url) window.location.href = url
  }
}
