import { Controller } from "@hotwired/stimulus"

// Stimulus controller that hooks into any form to:
//   1. Run real-time rule evaluation on field blur (debounced 400ms)
//   2. Intercept form submission, evaluate all rules, and show a modal
//      before allowing the save to proceed.
//
// Usage on a form wrapper element:
//   data-controller="rule-validation"
//   data-rule-validation-target-model-value="Valuation"
//   data-rule-validation-record-id-value="<%= @valuation.id || '' %>"
//   data-rule-validation-evaluate-url-value="<%= evaluate_validation_rules_path %>"
export default class extends Controller {
  // Values passed from the ERB template via data attributes
  static values = {
    targetModel:            String,
    recordId:               String,   // empty string for new records
    evaluateUrl:            String,
    // Optional CSS selector for a hidden element whose innerHTML is shown in the modal
    // when the form is about to submit. Rendered above rule items when warnings fire;
    // shown alone (as a confirmation step) when no rules fire.
    // Suppressed entirely when blockers fire (approval is already blocked).
    confirmMessageSelector: String
  }

  connect() {
    this._debounceTimer = null

    // Store bound references so they can be removed in disconnect()
    this._boundOnFieldBlur  = this._onFieldBlur.bind(this)
    this._boundOnFormSubmit = this._onFormSubmit.bind(this)
    this._blurFields        = []

    // Attach blur listeners to every input/select/textarea inside this element
    this.element.querySelectorAll("input, select, textarea").forEach(field => {
      field.addEventListener("blur", this._boundOnFieldBlur)
      this._blurFields.push(field)
    })

    // Intercept the form's submit event so we can show the modal first
    this._form = this.element.querySelector("form") || this.element
    this._form.addEventListener("submit", this._boundOnFormSubmit)
  }

  disconnect() {
    clearTimeout(this._debounceTimer)
    this._blurFields.forEach(field => field.removeEventListener("blur", this._boundOnFieldBlur))
    this._form?.removeEventListener("submit", this._boundOnFormSubmit)
  }

  // ── Real-time: field blur ──────────────────────────────────────────────────

  _onFieldBlur() {
    clearTimeout(this._debounceTimer)
    // Wait 400ms after the user leaves the field before calling the server,
    // so rapid tab-throughs don't spam requests
    this._debounceTimer = setTimeout(() => this._runEvaluation(false), 400)
  }

  // ── On save: intercept submit ─────────────────────────────────────────────

  async _onFormSubmit(event) {
    // If the form already has force_save set (user confirmed the modal), let it through
    const form = event.target
    if (form.querySelector("input[name='force_save']")?.value === "1") return

    event.preventDefault()

    const results = await this._runEvaluation(true)
    if (!results) return  // fetch failed — let normal submit proceed

    const { warnings, blockers } = results

    if (blockers.length === 0 && warnings.length === 0) {
      // No rule issues — if a confirm message is configured, show it before submitting
      const confirmHtml = this._confirmHtml()
      if (confirmHtml) {
        this._showModal({ warnings: [], blockers: [], form, confirmHtml })
        return
      }
      // No confirm message — submit immediately
      form.submit()
      return
    }

    // Show the modal; the modal's confirm button will resubmit with force_save=1.
    // Include the confirm message above warnings (omit it when blockers fire since approval is blocked).
    this._showModal({ warnings, blockers, form, confirmHtml: this._confirmHtml() })
  }

  // ── Evaluation fetch ──────────────────────────────────────────────────────

  // @param fullForm [Boolean] collect all form fields (true on submit, false on blur)
  // @return {warnings, blockers} or null on error
  async _runEvaluation(fullForm) {
    const form = this._form
    const formData = fullForm
      ? new FormData(form)
      : this._collectFields(form)

    const attributes = {}
    formData.forEach((value, key) => {
      // Strip Rails model prefix: "valuation[valuation_date]" → "valuation_date"
      const match = key.match(/\[(.+)\]$/)
      attributes[match ? match[1] : key] = value
    })

    try {
      const response = await fetch(this.evaluateUrlValue, {
        method:  "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token":  this._csrfToken()
        },
        body: JSON.stringify({
          target_model: this.targetModelValue,
          record_id:    this.recordIdValue || null,
          attributes
        })
      })

      if (!response.ok) return null

      const data = await response.json()

      // Update inline field indicators (yellow/red underlines)
      if (!fullForm) this._updateFieldIndicators(data)

      return data
    } catch (err) {
      console.warn("[rule-validation] evaluate fetch failed:", err)
      return null
    }
  }

  // ── Inline field indicators (real-time feedback) ──────────────────────────

  // Marks fields that appear in rule results with a coloured border and
  // removes marks from fields whose rules no longer fire.
  _updateFieldIndicators({ warnings, blockers }) {
    // Clear existing rule indicators first
    this.element.querySelectorAll(".rule-warning, .rule-blocker").forEach(el => {
      el.classList.remove("rule-warning", "rule-blocker")
    })

    const mark = (results, cssClass) => {
      results.forEach(r => {
        // Rule names follow the convention "<model>_<field>_<condition>",
        // so the second segment is often the field name — a best-effort heuristic
        const fieldGuess = r.rule_name.split("_").slice(1, -1).join("_")
        const field = this.element.querySelector(`[name*='${fieldGuess}']`)
        field?.closest(".form-group")?.classList.add(cssClass)
      })
    }

    mark(warnings, "rule-warning")
    mark(blockers,  "rule-blocker")
  }

  // ── Modal ─────────────────────────────────────────────────────────────────

  _showModal({ warnings, blockers, form, confirmHtml = null }) {
    document.getElementById("ruleValidationModal")?.remove()

    const hasBlockers  = blockers.length > 0
    const hasWarnings  = warnings.length > 0
    const hasRules     = hasBlockers || hasWarnings
    const confirmOnly  = !hasRules && !!confirmHtml

    // Icon: blue info when confirm-only; yellow/red warning triangle when rules fire
    const iconSvg = confirmOnly
      ? `<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" fill="#3b82f6" viewBox="0 0 16 16">
           <path d="M8 16A8 8 0 1 0 8 0a8 8 0 0 0 0 16zm.93-9.412-1 4.705c-.07.34.029.533.304.533.194 0 .487-.07.686-.246l-.088.416c-.287.346-.92.598-1.465.598-.703 0-1.002-.422-.808-1.319l.738-3.468c.064-.293.006-.399-.287-.47l-.451-.081.082-.381 2.29-.287zM8 5.5a1 1 0 1 1 0-2 1 1 0 0 1 0 2z"/>
         </svg>`
      : `<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" fill="${hasBlockers ? '#f87171' : '#fbbf24'}" viewBox="0 0 16 16">
           <path d="M8.982 1.566a1.13 1.13 0 0 0-1.96 0L.165 13.233c-.457.778.091 1.767.98 1.767h13.713c.889 0 1.438-.99.98-1.767L8.982 1.566zM8 5c.535 0 .954.462.9.995l-.35 3.507a.552.552 0 0 1-1.1 0L7.1 5.995A.905.905 0 0 1 8 5zm.002 6a1 1 0 1 1 0 2 1 1 0 0 1 0-2z"/>
         </svg>`

    const title = confirmOnly
      ? 'Confirm Approval'
      : hasBlockers ? 'Cannot Approve — Issues Found' : 'Review Before Approving'

    // confirmHtml shown above rule items when no blockers; omitted when blockers fire
    // (approval is blocked so the notification context is irrelevant)
    const confirmSection = (confirmHtml && !hasBlockers)
      ? `<div style="margin-bottom:${hasRules ? '0.75rem' : '0'};${hasRules ? 'padding-bottom:0.75rem;border-bottom:1px solid #f0f0f0' : ''}">${confirmHtml}</div>`
      : ''

    const ruleSection = hasRules ? `
      ${hasBlockers ? this._renderRuleItems(blockers, '#f87171', '#fff5f5') : ''}
      ${hasWarnings ? this._renderRuleItems(warnings, '#fbbf24', '#fffbeb') : ''}
      <p style="font-size:0.8rem;color:#888;margin-top:0.75rem;margin-bottom:0">
        ${hasBlockers
          ? 'Fix the issues above before approving.'
          : 'These are warnings only. You may still proceed by clicking <strong>Confirm &amp; Save</strong>.'}
      </p>` : ''

    const modal = document.createElement("div")
    modal.innerHTML = `
      <div class="modal fade" id="ruleValidationModal" tabindex="-1" aria-modal="true" role="dialog">
        <div class="modal-dialog modal-dialog-scrollable" style="max-width:680px">
          <div class="modal-content border-0" style="border-radius:10px;box-shadow:0 8px 30px rgba(0,0,0,0.12)">

            <div class="modal-header" style="border-bottom:1px solid #f0f0f0;padding:1rem 1.25rem 0.75rem">
              <div class="d-flex align-items-center gap-2">
                ${iconSvg}
                <h6 class="modal-title mb-0 fw-semibold" style="font-size:0.95rem;color:#1a1a1a">
                  ${title}
                </h6>
              </div>
              <button type="button" class="btn-close" style="width:0.75rem;height:0.75rem" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>

            <div class="modal-body" style="padding:1rem 1.25rem">
              ${confirmSection}${ruleSection}
            </div>

            <div class="modal-footer" style="border-top:1px solid #f0f0f0;padding:0.75rem 1.25rem;gap:0.5rem">
              <button type="button" class="btn btn-light btn-sm" data-bs-dismiss="modal"
                      style="font-size:0.85rem;color:#555;border:1px solid #ddd">
                Go Back
              </button>
              ${!hasBlockers ? `
                <button type="button" class="btn btn-primary btn-sm fw-semibold" id="ruleModalConfirm"
                        style="font-size:0.85rem">
                  Confirm &amp; Save
                </button>` : ''
              }
            </div>

          </div>
        </div>
      </div>
    `

    document.body.appendChild(modal.firstElementChild)

    const bsModal = new bootstrap.Modal(document.getElementById("ruleValidationModal"))
    bsModal.show()

    document.getElementById("ruleModalConfirm")?.addEventListener("click", () => {
      bsModal.hide()
      let hiddenFlag = form.querySelector("input[name='force_save']")
      if (!hiddenFlag) {
        hiddenFlag = document.createElement("input")
        hiddenFlag.type = "hidden"
        hiddenFlag.name = "force_save"
        form.appendChild(hiddenFlag)
      }
      hiddenFlag.value = "1"
      form.submit()
    })
  }

  // Returns the innerHTML of the element matching confirmMessageSelectorValue, or null.
  _confirmHtml() {
    if (!this.hasConfirmMessageSelectorValue || !this.confirmMessageSelectorValue) return null
    return document.querySelector(this.confirmMessageSelectorValue)?.innerHTML?.trim() || null
  }

  // Each rule on its own row: pastel background tint, coloured left border, plain dark text
  _renderRuleItems(items, accentColor, bgColor = '#fff') {
    return items.map(r => `
      <div style="
        background:${bgColor}; border:1px solid ${accentColor}33;
        border-left:3px solid ${accentColor};
        border-radius:6px; padding:0.65rem 0.85rem;
        margin-bottom:0.5rem;
      ">
        <span style="font-size:0.85rem;color:#374151;line-height:1.5">${r.message}</span>
      </div>
    `).join("")
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  _csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  // Collects all named form fields — used for blur-triggered evaluation so we
  // send the current field values without waiting for a full form submit.
  _collectFields(form) {
    const fd = new FormData()
    form.querySelectorAll("input:not([type=submit]), select, textarea").forEach(field => {
      if (field.name) fd.append(field.name, field.value)
    })
    return fd
  }
}
