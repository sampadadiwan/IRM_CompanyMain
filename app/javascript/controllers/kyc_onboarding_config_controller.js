/**
 * Stimulus controller for the KYC Onboarding Agent's Document Verification
 * Setup table. Serialises the 3-column mapping rows (Document dropdown,
 * extraction prompt, Field-to-verify dropdown) into the hidden json_fields
 * input on every edit. Follows the same pattern as
 * kyc_doc_extractor_config_controller.
 */
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["jsonField", "rulesBody"]

  connect() {
    this.syncConfig()
  }

  /**
   * Reads every rule row from each form-type tbody, serialises them into
   * json_fields["doc_verification_rules"] keyed by form_type_id, and writes
   * the merged JSON back to the hidden input — preserving all other keys
   * (toggles, required_docs, etc.).
   */
  syncConfig() {
    const rules = {}

    this.rulesBodyTargets.forEach(tbody => {
      const formTypeId = tbody.dataset.formTypeId
      const rows = tbody.querySelectorAll("tr[data-rule-row]")
      const entries = Array.from(rows).map(row => ({
        doc_label:    row.querySelector('[data-field="doc_label"]')?.value?.trim()    || "",
        prompt:       row.querySelector('[data-field="prompt"]')?.value?.trim()       || "",
        target_field: row.querySelector('[data-field="target_field"]')?.value?.trim() || ""
      })).filter(r => r.doc_label)

      if (entries.length > 0) rules[formTypeId] = entries
    })

    const existing = JSON.parse(this.jsonFieldTarget.value || "{}")
    this.jsonFieldTarget.value = JSON.stringify({
      ...existing,
      doc_verification_rules: rules
    })
    console.log("[KycOnboardingConfig] doc_verification_rules:", JSON.stringify(rules, null, 2))
  }

  /**
   * Appends a blank rule row by cloning the <template> associated with
   * the clicked "+ Add Rule" button's form-type section.
   */
  addRule(event) {
    const tbody = event.target.closest("[data-form-type-section]")
                              .querySelector("[data-kyc-onboarding-config-target='rulesBody']")
    const templateId = tbody.dataset.templateId
    const template = document.getElementById(templateId)
    if (!template) return

    tbody.appendChild(template.content.cloneNode(true))
    this.syncConfig()
  }

  /**
   * Removes the clicked row and re-syncs the hidden field.
   */
  removeRule(event) {
    event.target.closest("tr[data-rule-row]").remove()
    this.syncConfig()
  }
}
