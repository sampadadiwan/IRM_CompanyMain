import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["jsonField", "fundsBody", "fundTemplate"]

  connect() {
    this.updateConfig()
  }

  addFund() {
    const template = this.fundTemplateTarget.content.cloneNode(true)
    this.fundsBodyTarget.appendChild(template)
    this.updateConfig()
  }

  removeFund(event) {
    event.target.closest("tr").remove()
    this.updateConfig()
  }

  updateConfig() {
    const config = { funds: this._buildFunds() }
    this.jsonFieldTarget.value = JSON.stringify(config)
  }

  _buildFunds() {
    const rows = this.fundsBodyTarget.querySelectorAll("tr")
    return Array.from(rows).map(row => {
      const fundId = row.querySelector('[data-field="fund_id"]')?.value
      const fundName = row.querySelector('[data-field="fund_id"]')?.selectedOptions[0]?.text
      const cashDays = row.querySelector('[data-field="cash_accounts_max_days"]')?.value
      const proformaDays = row.querySelector('[data-field="proforma_max_days"]')?.value
      return {
        fund_id: fundId,
        name: fundName || "",
        staleness_thresholds: {
          cash_accounts_max_days: parseInt(cashDays) || 30,
          proforma_max_days: parseInt(proformaDays) || 90
        }
      }
    }).filter(f => f.fund_id)
  }
}
