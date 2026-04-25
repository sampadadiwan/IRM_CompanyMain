import { Controller } from "@hotwired/stimulus"
import { post } from "@rails/request.js"

export default class extends Controller {
  static targets = ["fundIds", "results"]
  static values = { url: String }

  async fetch(event) {
    event.preventDefault()
    const fundIds = $(this.fundIdsTarget).val()
    const nameField = document.querySelector('[data-generate-formula-target="name"]')
    const ruleTypeField = document.querySelector('[data-generate-formula-target="ruleType"]')
    
    const name = nameField ? nameField.value : ""
    const ruleType = ruleTypeField ? ruleTypeField.value : ""

    if (!fundIds || fundIds.length === 0) {
      alert("Please select at least one fund")
      return
    }

    const response = await post(this.urlValue, {
      body: JSON.stringify({
        fund_ids: fundIds,
        name: name,
        rule_type: ruleType
      }),
      responseKind: "turbo-stream"
    })
  }
}
