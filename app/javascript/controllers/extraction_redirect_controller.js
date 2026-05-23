import { Controller } from "@hotwired/stimulus"

// Navigates to `urlValue` as soon as it connects.
// Used by KycDocExtractorJob to redirect the processing page once extraction completes.
export default class extends Controller {
  static values = { url: String }

  connect() {
    Turbo.visit(this.urlValue)
  }
}
