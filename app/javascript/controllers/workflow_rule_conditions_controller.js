import { Controller } from "@hotwired/stimulus"
import { formatLocaleDate } from "custom/locale_date_format"

// Row editor for an auto-assignment rule's conditions: one row per condition (field / operator /
// value), all joined by AND. Every edit is written as a JSON array into the `json` textarea, which is
// the field the form actually submits (workflow_auto_assignment_rule[conditions_json]) — so with JS
// off the textarea is simply visible and usable, and "View as JSON" just shows it.
//
// The field list (fields, kinds, operators, options) comes from WorkflowRuleFields#to_builder_json:
// the same list the server validates against, so the rows can only offer what a save accepts.
// Design: openspec/changes/workflow-rule-condition-builder/design.md#-rule-form
export default class extends Controller {
  static targets = ["rows", "json", "rowsPanel", "jsonPanel", "toggle", "jsonError", "dateTemplate"]
  static values  = { fields: Object }

  connect() {
    this.fieldsByKey = new Map(this.fieldsValue.fields.map((f) => [f.key, f]))
    this.noValueOperators = this.fieldsValue.no_value_operators
    this.listOperators = this.fieldsValue.list_operators

    // Start on rows when the saved/submitted JSON is a readable list; otherwise stay on the JSON so
    // the admin sees (and can fix) exactly what was submitted
    const conditions = this.parseJson(this.jsonTarget.value)
    if (conditions) {
      this.renderRows(conditions)
      this.showRows()
    } else {
      this.showJson(true)
    }
  }

  // ── Mode toggle ────────────────────────────────────────────────────────────

  toggle(event) {
    event.preventDefault()
    if (this.jsonMode) {
      // Back to rows only if the JSON can be read as conditions
      const conditions = this.parseJson(this.jsonTarget.value)
      if (!conditions) {
        this.showJson(true)
        return
      }
      this.renderRows(conditions)
      this.showRows()
    } else {
      this.serialize()
      this.showJson(false)
    }
  }

  showRows() {
    this.jsonMode = false
    this.rowsPanelTarget.classList.remove("d-none")
    this.jsonPanelTarget.classList.add("d-none")
    this.jsonErrorTarget.classList.add("d-none")
    this.toggleTarget.textContent = "View as JSON"
  }

  showJson(invalid) {
    this.jsonMode = true
    this.rowsPanelTarget.classList.add("d-none")
    this.jsonPanelTarget.classList.remove("d-none")
    this.jsonErrorTarget.classList.toggle("d-none", !invalid)
    this.toggleTarget.textContent = "View as rows"
  }

  // A list of objects with attribute + operator, or null
  parseJson(text) {
    if (!text || !text.trim()) return []
    try {
      const parsed = JSON.parse(text)
      const ok = Array.isArray(parsed) && parsed.every((c) => c && typeof c === "object" && !Array.isArray(c) && c.attribute && c.operator)
      return ok ? parsed : null
    } catch (_e) {
      return null
    }
  }

  // ── Rows ───────────────────────────────────────────────────────────────────

  renderRows(conditions) {
    this.rowsTarget.replaceChildren()
    conditions.forEach((condition) => this.rowsTarget.appendChild(this.buildRow(condition)))
    this.serialize()
  }

  add(event) {
    event.preventDefault()
    this.rowsTarget.appendChild(this.buildRow({ attribute: "", operator: "", value: "" }))
    this.serialize()
  }

  remove(event) {
    event.preventDefault()
    event.currentTarget.closest(".rule-condition").remove()
    this.serialize()
  }

  // One condition row. A condition whose field is not on the list keeps its raw JSON and shows as
  // "Unknown field" — the server refuses it on save, so the admin has to remove or change it.
  buildRow(condition) {
    const row = document.createElement("div")
    row.className = "rule-condition d-flex flex-wrap gap-2 align-items-start mb-2"

    const field = this.fieldsByKey.get(condition.attribute)
    if (condition.attribute && !field) {
      row.classList.add("rule-condition-unknown")
      row.dataset.raw = JSON.stringify(condition)
      const message = document.createElement("div")
      message.className = "alert alert-danger py-1 px-2 mb-0 flex-grow-1"
      message.textContent = `Unknown field: ${condition.attribute.replace(/^json_fields\./, "")} — remove or change it`
      row.append(message, this.removeButton())
      return row
    }

    row.append(this.fieldSelect(condition.attribute), this.operatorSelect(field, condition.operator),
               this.valueHolder(), this.removeButton())
    this.renderValue(row, condition.value)
    return row
  }

  // Field dropdown, grouped as the field list groups them ("KYC fields", "Custom fields")
  fieldSelect(selected) {
    const select = this.select("rule-field", "Field")
    select.appendChild(this.option("", "Choose a field…"))
    const groups = new Map()
    this.fieldsValue.fields.forEach((f) => {
      if (!groups.has(f.group)) {
        const optgroup = document.createElement("optgroup")
        optgroup.label = f.group
        groups.set(f.group, optgroup)
        select.appendChild(optgroup)
      }
      groups.get(f.group).appendChild(this.option(f.key, f.label))
    })
    select.value = selected || ""
    select.dataset.action = "change->workflow-rule-conditions#fieldChanged"
    return select
  }

  operatorSelect(field, selected) {
    const select = this.select("rule-operator", "Operator")
    ;(field?.operators || []).forEach((op) => select.appendChild(this.option(op.value, op.label)))
    if (field) select.value = field.operators.some((op) => op.value === selected) ? selected : field.operators[0].value
    select.disabled = !field
    select.dataset.action = "change->workflow-rule-conditions#operatorChanged"
    return select
  }

  valueHolder() {
    const holder = document.createElement("div")
    holder.className = "rule-value-holder flex-grow-1"
    return holder
  }

  removeButton() {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "btn btn-sm btn-light text-danger rule-remove"
    button.title = "Remove condition"
    button.setAttribute("aria-label", "Remove condition")
    button.dataset.action = "click->workflow-rule-conditions#remove"
    const icon = document.createElement("i")
    icon.className = "ti ti-x"
    button.appendChild(icon)
    return button
  }

  // A new field: its operators replace the old ones and the value starts empty
  fieldChanged(event) {
    const row = event.currentTarget.closest(".rule-condition")
    const field = this.fieldsByKey.get(event.currentTarget.value)
    row.querySelector(".rule-operator").replaceWith(this.operatorSelect(field, null))
    this.renderValue(row, "")
    this.serialize()
  }

  // A new operator keeps whatever value still fits (one value ↔ a list)
  operatorChanged(event) {
    const row = event.currentTarget.closest(".rule-condition")
    this.renderValue(row, this.readValue(row))
    this.serialize()
  }

  // ── Value inputs (by field kind and operator) ──────────────────────────────

  renderValue(row, value) {
    const holder = row.querySelector(".rule-value-holder")
    holder.replaceChildren()
    const field = this.fieldsByKey.get(row.querySelector(".rule-field").value)
    const operator = row.querySelector(".rule-operator").value
    // is blank / is present: no value at all
    if (!field || this.noValueOperators.includes(operator)) return

    const list = this.listOperators.includes(operator)
    const values = (Array.isArray(value) ? value : [value]).filter((v) => v !== undefined && v !== null && v !== "").map(String)
    let input

    switch (field.kind) {
      case "reference":
      case "option":
      case "multi_option":
        input = this.select("rule-value", field.label)
        if (list) input.multiple = true
        else input.appendChild(this.option("", "Choose…"))
        field.options.forEach((o) => {
          const option = this.option(o.value, o.label)
          option.selected = values.includes(o.value)
          input.appendChild(option)
        })
        break
      case "boolean":
        input = this.select("rule-value", field.label)
        input.append(this.option("", "Choose…"), this.option("true", "Yes"), this.option("false", "No"))
        input.value = values[0] || ""
        break
      case "date":
        holder.appendChild(this.dateInput(values[0] || ""))
        return
      case "number":
        input = document.createElement("input")
        input.type = list ? "text" : "number"
        input.step = "any"
        input.className = "form-control rule-value"
        input.value = values.join(", ")
        break
      default:
        input = document.createElement("input")
        input.type = "text"
        input.className = "form-control rule-value"
        input.placeholder = list ? "Comma-separated values" : ""
        input.value = values.join(", ")
    }
    input.setAttribute("aria-label", field.label)
    input.dataset.action = "change->workflow-rule-conditions#serialize input->workflow-rule-conditions#serialize"
    holder.appendChild(input)
  }

  // The app's own locale date input (date_field_tag), cloned from the form's <template>: the user
  // types or picks in the locale format, the hidden ISO input carries the value
  dateInput(iso) {
    const fragment = this.dateTemplateTarget.content.cloneNode(true)
    const hidden = fragment.querySelector("[data-locale-date-target='hidden']")
    const display = fragment.querySelector("[data-locale-date-target='display']")
    const picker = fragment.querySelector("input[type='date']")
    // Template ids/names must not repeat or submit: the textarea is the only submitted field
    display.removeAttribute("id")
    hidden.removeAttribute("name")
    hidden.classList.add("rule-value")
    hidden.value = iso
    if (picker) picker.value = iso
    display.value = iso ? formatLocaleDate(iso) : ""
    display.classList.add("rule-date-display")
    hidden.dataset.action = "change->workflow-rule-conditions#serialize"
    return fragment
  }

  readValue(row) {
    const input = row.querySelector(".rule-value")
    if (!input) return ""
    if (input.multiple) return Array.from(input.selectedOptions).map((o) => o.value)
    return input.value
  }

  // ── Serialising ────────────────────────────────────────────────────────────

  serialize() {
    const rows = Array.from(this.rowsTarget.querySelectorAll(".rule-condition"))
    // A row whose field is not picked yet is not a condition
    const conditions = rows.filter((row) => row.dataset.raw || row.querySelector(".rule-field").value).map((row) => {
      // Unknown rows go back exactly as they came, for the server to refuse
      if (row.dataset.raw) return JSON.parse(row.dataset.raw)

      const attribute = row.querySelector(".rule-field").value
      const operator = row.querySelector(".rule-operator").value
      const condition = { attribute, operator }
      if (this.noValueOperators.includes(operator)) return condition

      let value = this.readValue(row)
      // A typed list ("India, UK") is stored as an array
      if (this.listOperators.includes(operator) && !Array.isArray(value)) {
        value = value.split(",").map((v) => v.trim()).filter((v) => v !== "")
      }
      condition.value = value
      return condition
    })
    this.jsonTarget.value = JSON.stringify(conditions, null, 2)
  }

  // ── DOM helpers ────────────────────────────────────────────────────────────

  select(className, label) {
    const select = document.createElement("select")
    select.className = `form-select ${className}`
    select.style.maxWidth = "22rem"
    select.setAttribute("aria-label", label)
    return select
  }

  option(value, label) {
    const option = document.createElement("option")
    option.value = value
    option.textContent = label
    return option
  }
}
