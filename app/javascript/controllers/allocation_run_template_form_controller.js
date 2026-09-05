import { Controller } from "@hotwired/stimulus"

// Keeps the "Statement document" select on the allocation run template form in step with
// the chosen fund: statement documents belong to a fund, so switching the fund refills the
// options from the JSON endpoint (allocation_run_templates#statement_documents).
//
//   <form data-controller="allocation-run-template-form"
//         data-allocation-run-template-form-documents-url-value="/allocation_run_templates/statement_documents">
//     <select data-allocation-run-template-form-target="fund"
//             data-action="change->allocation-run-template-form#fundChanged">
//     <select data-allocation-run-template-form-target="document">
export default class extends Controller {
  static targets = ["fund", "document"]
  static values = { documentsUrl: String }

  async fundChanged() {
    const fundId = this.fundTarget.value
    const select = this.documentTarget
    select.innerHTML = ""
    select.appendChild(new Option("— select a document —", ""))
    if (!fundId) return

    try {
      const response = await fetch(`${this.documentsUrlValue}?fund_id=${encodeURIComponent(fundId)}`, {
        headers: { Accept: "application/json" }
      })
      if (!response.ok) return
      const docs = await response.json()
      docs.forEach((doc) => select.appendChild(new Option(doc.name, doc.id)))
      if (docs.length === 0) {
        select.appendChild(new Option("No statement documents on this fund", "", false, false)).disabled = true
      }
    } catch (error) {
      console.error("allocation-run-template-form: could not load statement documents", error)
    }
  }
}
