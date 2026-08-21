import { Controller } from "@hotwired/stimulus"

// Warns the user before a NEW sell PI is saved with the same date/quantity/amount as an
// existing sell. Without this, two duplicate sells could each queue their own background
// attribution job and (before the AttributionService row-locking fix) race on the same buy
// lot, leaving the second sell with a silently wrong realized gain — and re-saving could
// never fix it, since PortfolioInvestmentUpdate never re-runs attribution. This is the UI
// half of that bug report: block the save and ask for a Ref ID that disambiguates the two.
//
// Usage — wrap the PI form:
//   data-controller="portfolio-investment-duplicate-check"
//   data-portfolio-investment-duplicate-check-check-url-value="<%= check_duplicate_sell_portfolio_investments_path %>"
export default class extends Controller {
  static values = { checkUrl: String }

  connect() {
    this._form = this.element.querySelector("form") || this.element
    this._boundOnSubmit = this._onSubmit.bind(this)
    this._form.addEventListener("submit", this._boundOnSubmit)
  }

  disconnect() {
    this._form?.removeEventListener("submit", this._boundOnSubmit)
  }

  async _onSubmit(event) {
    const form = event.target

    // Already confirmed via the modal (or a previous pass found no duplicate) — let it through
    if (form.querySelector("input[name='duplicate_confirmed']")?.value === "1") return

    // Rails only renders a _method override hidden field for PATCH/PUT/DELETE forms, so its
    // absence means this is a create (new record). Only new sells can hit this race — edits
    // go through a path that can't touch attribution, and buys have no gain to corrupt.
    const isNewRecord = !form.querySelector("input[name='_method']")
    const quantityField = form.querySelector("#portfolio_investment_quantity")
    const quantity = parseFloat(quantityField?.value)
    if (!isNewRecord || !quantityField || Number.isNaN(quantity) || quantity >= 0) return

    event.preventDefault()

    const usedRefIds = await this._checkDuplicate(form)

    // A broken/unreachable check endpoint must not block a legitimate save — mirrors the
    // same fail-open policy the rule-validation controller uses for its evaluate endpoint.
    if (usedRefIds === null || usedRefIds.length === 0) {
      this._submitConfirmed(form)
      return
    }

    this._showModal(form, usedRefIds)
  }

  async _checkDuplicate(form) {
    const formData = new FormData(form)
    const field = (name) => formData.get(`portfolio_investment[${name}]`)

    try {
      const response = await fetch(this.checkUrlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": this._csrfToken() },
        body: JSON.stringify({
          portfolio_company_id: field("portfolio_company_id"),
          investment_instrument_id: field("investment_instrument_id"),
          fund_id: field("fund_id"),
          investment_date: field("investment_date"),
          quantity: field("quantity"),
          ex_expenses_base_amount: field("ex_expenses_base_amount")
        })
      })
      if (!response.ok) return null

      const data = await response.json()
      return data.duplicate ? data.used_ref_ids : []
    } catch (err) {
      console.warn("[portfolio-investment-duplicate-check] check failed:", err)
      return null
    }
  }

  _showModal(form, usedRefIds) {
    document.getElementById("piDuplicateModal")?.remove()

    const modal = document.createElement("div")
    modal.innerHTML = `
      <div class="modal fade" id="piDuplicateModal" tabindex="-1" aria-modal="true" role="dialog">
        <div class="modal-dialog" role="document">
          <div class="modal-content">
            <div class="modal-header">
              <h5 class="modal-title">Possible Duplicate Investment</h5>
              <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <div class="modal-body">
              <div class="action-summary__intro">
                A portfolio investment with the same date, quantity, and amount already exists.
                To save this as a separate transaction, please enter a Ref ID different from the original.
              </div>
              <div class="action-summary__list">
                <div class="action-summary__item action-summary__item--amber">
                  <div class="action-summary__icon"><i class="fas fa-hashtag"></i></div>
                  <div>
                    <div class="action-summary__title">Ref ID</div>
                    <div class="action-summary__desc">
                      <input type="number" class="form-control" id="piDuplicateRefId" step="1" min="1">
                      <small class="text-muted d-block mt-1">Already used for this transaction: ${usedRefIds.join(", ")}</small>
                      <small class="text-danger d-none" id="piDuplicateRefIdError">Enter a Ref ID different from the one(s) already used.</small>
                    </div>
                  </div>
                </div>
              </div>
            </div>
            <div class="modal-footer">
              <button type="button" class="btn btn-outline-secondary" data-bs-dismiss="modal">Cancel</button>
              <button type="button" class="btn btn-primary" id="piDuplicateConfirm">Yes, Save Anyway</button>
            </div>
          </div>
        </div>
      </div>
    `

    document.body.appendChild(modal.firstElementChild)
    const bsModal = new bootstrap.Modal(document.getElementById("piDuplicateModal"))
    bsModal.show()

    document.getElementById("piDuplicateConfirm").addEventListener("click", () => {
      const input = document.getElementById("piDuplicateRefId")
      const refId = parseInt(input.value, 10)
      const usedIds = usedRefIds.map(Number)

      if (!refId || usedIds.includes(refId)) {
        document.getElementById("piDuplicateRefIdError").classList.remove("d-none")
        return
      }

      this._setRefId(form, refId)
      bsModal.hide()
      this._submitConfirmed(form)
    })
  }

  _setRefId(form, refId) {
    let field = form.querySelector("input[name='portfolio_investment[ref_id]']")
    if (!field) {
      field = document.createElement("input")
      field.type = "hidden"
      field.name = "portfolio_investment[ref_id]"
      form.appendChild(field)
    }
    field.value = refId
  }

  // Sets a bypass flag and resubmits so the interceptor above lets it through this time.
  _submitConfirmed(form) {
    let flag = form.querySelector("input[name='duplicate_confirmed']")
    if (!flag) {
      flag = document.createElement("input")
      flag.type = "hidden"
      flag.name = "duplicate_confirmed"
      form.appendChild(flag)
    }
    flag.value = "1"
    form.requestSubmit()
  }

  _csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
