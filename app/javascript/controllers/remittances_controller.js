import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  filter() {
    const status = document.getElementById("status").value;
    const verified = document.getElementById("verified").value;

    const baseUrl = this.data.get("filterSrc");
    if (!baseUrl) {
      console.warn("Missing data-filter-src in remittances controller");
      return;
    }
    const url = new URL(baseUrl, window.location.origin);

    // Update or remove 'status' param
    if (status) {
      url.searchParams.set("status", status);
    } else {
      url.searchParams.delete("status");
    }

    // Update or remove 'verified' param
    if (verified) {
      url.searchParams.set("verified", verified);
    } else {
      url.searchParams.delete("verified");
    }

    const frame = document.getElementById("capital_remittances_frame");
    frame.setAttribute("src", url.toString());
  }
}
