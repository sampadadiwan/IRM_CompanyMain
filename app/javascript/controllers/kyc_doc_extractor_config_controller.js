import { Controller } from "@hotwired/stimulus"

// Manages the KycDocExtractorAgent configuration UI.
// Serialises overwrite_mode + extraction_rules (keyed by form_type_id) into a single hidden JSON field.
export default class extends Controller {
  static targets = ["jsonField", "overwriteMode", "rulesBody"]

  connect() {
    this.syncConfig()
  }

  // Called whenever any input changes
  syncConfig() {
    const overwriteMode = this.overwriteModeTarget.value
    const extractionRules = {}

    this.rulesBodyTargets.forEach(tbody => {
      const formTypeId = tbody.dataset.formTypeId
      const rows = tbody.querySelectorAll("tr[data-rule-row]")
      const rules = Array.from(rows).map(row => ({
        doc_label:    row.querySelector('[data-field="doc_label"]')?.value?.trim()    || "",
        prompt:       row.querySelector('[data-field="prompt"]')?.value?.trim()       || "",
        target_field: row.querySelector('[data-field="target_field"]')?.value?.trim() || ""
      })).filter(r => r.doc_label || r.prompt || r.target_field)

      if (rules.length > 0) extractionRules[formTypeId] = rules
    })

    const existing = JSON.parse(this.jsonFieldTarget.value || "{}")
    // Preserve any other keys (e.g. chat_config) already in json_fields
    this.jsonFieldTarget.value = JSON.stringify({
      ...existing,
      overwrite_mode: overwriteMode,
      extraction_rules: extractionRules
    })
  }

  addRule(event) {
    const tbody = event.target.closest("[data-form-type-section]")
                              .querySelector("[data-kyc-doc-extractor-config-target='rulesBody']")
    const templateId = tbody.dataset.templateId
    const template   = document.getElementById(templateId)
    if (!template) return

    const clone = template.content.cloneNode(true)
    tbody.appendChild(clone)
    this.syncConfig()
  }

  removeRule(event) {
    event.target.closest("tr[data-rule-row]").remove()
    this.syncConfig()
  }
}
