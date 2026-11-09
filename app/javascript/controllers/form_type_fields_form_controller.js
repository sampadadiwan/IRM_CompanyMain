import { Controller } from "@hotwired/stimulus"
import { markSaving } from "custom/side_panel"

// ③ The custom fields list in the side panel — openspec/changes/grid-columns-inline-settings (phase 4).
// Everything stays in the browser until Save: drag to reorder, rename, Required / Read only / Internal, help text,
// remove (and undo) and add. On submit the list goes to the server as one JSON array.
export default class extends Controller {
  static targets = ["list", "fields", "count", "removeNote", "newLabel", "newType", "newOptions", "optionsBox"]

  connect() {
    this.updateCount()
    this.bindDrag()
  }

  toggleFlag(event) {
    const button = event.currentTarget
    const row = button.closest("[data-form-type-fields-row]")
    const on = !button.classList.contains("on")
    button.classList.toggle("on", on)
    button.setAttribute("aria-pressed", on ? "true" : "false")
    row.dataset[this.flagKey(button.dataset.flag)] = on ? "true" : "false"
  }

  toggleDetails(event) {
    const row = event.currentTarget.closest("[data-form-type-fields-row]")
    const details = row.querySelector("[data-grid-columns-details]")
    details.classList.toggle("d-none")
    row.classList.toggle("open", !details.classList.contains("d-none"))
  }

  // H14 — remove marks the row (struck through) until Save; ↶ keeps it. A new row is simply dropped.
  toggleRemove(event) {
    const row = event.currentTarget.closest("[data-form-type-fields-row]")
    if (!row.dataset.id) { row.remove(); this.updateCount(); return }
    const removed = row.dataset.removed !== "true"
    row.dataset.removed = removed ? "true" : "false"
    row.classList.toggle("removed", removed)
    event.currentTarget.querySelector("i").className = `ti ${removed ? "ti-arrow-back-up" : "ti-x"}`
    this.removeNoteTarget.classList.toggle("d-none", !this.rows().some((r) => r.dataset.removed === "true"))
    this.updateCount()
  }

  // M14 ⑨ H18 — the payout field choice (in the row's details) lights the row's bank icon
  payoutChanged(event) {
    const row = event.currentTarget.closest("[data-form-type-fields-row]")
    const flag = row.querySelector("[data-payout-flag]")
    if (flag) flag.classList.toggle("on", event.currentTarget.value !== "")
  }

  typeChanged() {
    this.optionsBoxTarget.classList.toggle("d-none", this.newTypeTarget.value !== "Select")
  }

  // H11 — a new field at the end of the list; X14 — no label, no field
  add() {
    const label = this.newLabelTarget.value.trim()
    if (!label) { this.newLabelTarget.focus(); this.newLabelTarget.reportValidity?.(); return }
    const row = this.rowElement({ label, fieldType: this.newTypeTarget.value, options: this.newOptionsTarget.value })
    row.classList.add("added")
    this.listTarget.appendChild(row)
    this.newLabelTarget.value = ""
    this.newOptionsTarget.value = ""
    this.updateCount()
  }

  serialise(event) {
    const fields = this.rows().filter((row) => row.dataset.locked !== "true").map((row) => {
      const data = {
        label: row.querySelector("[data-form-type-fields-label]").value,
        help_text: row.querySelector("[data-form-type-fields-help]").value,
        required: row.dataset.required === "true",
        read_only: row.dataset.readOnly === "true",
        internal: row.dataset.internal === "true"
      }
      // M14 ⑨ — a KYC text field's payout mark ("code" / "account" / "" for none); the server refuses an unmark
      // unless the user is CapHive support
      const payout = row.querySelector("[data-form-type-fields-payout]")
      if (payout) data.payout_field = payout.value
      if (row.dataset.id) {
        data.id = row.dataset.id
        if (row.dataset.removed === "true") data._destroy = true
      } else {
        data.field_type = row.dataset.fieldType
        data.options = row.dataset.options
      }
      return data
    })
    this.fieldsTarget.value = JSON.stringify(fields)
    markSaving(event.target)
  }

  rows() {
    return Array.from(this.listTarget.querySelectorAll("[data-form-type-fields-row]"))
  }

  updateCount() {
    const n = this.rows().filter((row) => row.dataset.removed !== "true").length
    this.countTarget.textContent = `${n} field${n === 1 ? "" : "s"}`
  }

  flagKey(flag) {
    return { required: "required", read_only: "readOnly", internal: "internal" }[flag]
  }

  // A new row, the same markup as form_type_fields/_row
  rowElement({ label, fieldType, options }) {
    const li = document.createElement("li")
    li.className = "grid-columns-row"
    li.dataset.formTypeFieldsRow = ""
    li.dataset.fieldType = fieldType
    li.dataset.options = options || ""
    li.dataset.locked = "false"
    li.dataset.removed = "false"
    li.dataset.required = "false"
    li.dataset.readOnly = "false"
    li.dataset.internal = "false"
    li.draggable = true
    const flags = [["required", "ti-asterisk", "Required"], ["read_only", "ti-lock", "Read only"], ["internal", "ti-eye-off", "Internal: hidden from investors"]]
      .map(([flag, icon, title]) => `<button type="button" class="form-type-fields-flag" data-flag="${flag}" data-action="form-type-fields-form#toggleFlag" title="${title}" aria-label="${title}" aria-pressed="false"><i class="ti ${icon}"></i></button>`).join("")
    li.innerHTML = `
      <div class="grid-columns-main">
        <i class="ti ti-grip-vertical grid-columns-handle" title="Drag to reorder" aria-hidden="true"></i>
        <div class="grid-columns-name"><input type="text" maxlength="254" data-form-type-fields-label><div class="grid-columns-key"></div></div>
        <span class="grid-columns-chip" data-type></span>
        ${flags}
        <button type="button" class="grid-columns-icon-btn" data-action="form-type-fields-form#toggleDetails" title="Help text"><i class="ti ti-chevron-down"></i></button>
        <button type="button" class="grid-columns-remove" data-action="form-type-fields-form#toggleRemove" title="Remove"><i class="ti ti-x"></i></button>
      </div>
      <div class="grid-columns-details d-none" data-grid-columns-details>
        <input type="text" class="form-control form-control-sm" placeholder="Help text shown under the field" data-form-type-fields-help>
      </div>`
    li.querySelector("[data-form-type-fields-label]").value = label
    li.querySelector(".grid-columns-key").textContent = "new field"
    li.querySelector("[data-type]").textContent = fieldType
    return li
  }

  bindDrag() {
    this.listTarget.addEventListener("dragstart", (event) => {
      const row = event.target.closest("[data-form-type-fields-row]")
      if (!row || row.dataset.locked === "true") { event.preventDefault(); return }
      this.dragged = row
      row.classList.add("dragging")
      event.dataTransfer.effectAllowed = "move"
      event.dataTransfer.setData("text/plain", row.dataset.name || "")
    })
    this.listTarget.addEventListener("dragover", (event) => {
      if (this.dragged && event.target.closest("[data-form-type-fields-row]")) event.preventDefault()
    })
    this.listTarget.addEventListener("drop", (event) => {
      const target = event.target.closest("[data-form-type-fields-row]")
      if (!this.dragged || !target || target === this.dragged) return
      event.preventDefault()
      const box = target.getBoundingClientRect()
      const after = event.clientY > box.top + box.height / 2
      target.parentNode.insertBefore(this.dragged, after ? target.nextSibling : target)
    })
    this.listTarget.addEventListener("dragend", () => {
      this.rows().forEach((row) => row.classList.remove("dragging"))
      this.dragged = null
    })
  }
}
