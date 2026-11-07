import { Controller } from "@hotwired/stimulus"
import { markSaving } from "custom/side_panel"

// ③ The columns list in the side panel — openspec/changes/grid-columns-inline-settings (card ③).
// Everything here stays in the browser until Save: drag to reorder, rename a heading, remove, add from the
// grouped list, reset to the page's standard columns. On submit the list goes to the server as one JSON array:
// a saved row by id (its key never comes from the browser), a new or standard row by key. Locked rows (E2,
// always shown on this page) are not sent.
const clean = (key) => (key || "").split(";")[0].trim()

export default class extends Controller {
  static targets = ["list", "rows", "reset", "resetNote", "add", "count", "standard", "derivedLabel", "derivedKey", "derivedType"]

  connect() {
    // Options already listed leave "Add a column"; kept aside to come back when their row is removed
    this.parked = new Map()
    this.syncOptions()
    this.updateCount()
    this.bindDrag()
    // Renaming a heading is an edit (it cancels a pending reset)
    this.listTarget.addEventListener("input", () => this.edited())
    this.initSearch()
  }

  disconnect() {
    if (this.select2) this.select2.select2("destroy")
  }

  // The add list is searchable (select2), its dropdown kept inside the panel so it can take focus
  initSearch() {
    const $ = window.jQuery
    if (!$ || !$.fn.select2) return
    this.select2 = $(this.addTarget)
    this.select2.select2({ width: "100%", dropdownParent: $(this.element.closest(".offcanvas") || document.body) })
    this.select2.on("select2:select", () => this.add())
  }

  // Add the picked column at the end of the list (H2, E10)
  add() {
    const option = this.addTarget.selectedOptions[0]
    if (!option || !option.value) return
    const row = this.rowElement({ key: option.value, label: option.dataset.label, type: option.dataset.type })
    row.classList.add("added")
    this.listTarget.appendChild(row)
    this.addTarget.value = ""
    if (this.select2) this.select2.val("").trigger("change.select2")
    this.syncOptions()
    this.edited()
  }

  // H18 — add a derived field: a heading, a key the user types and a data type
  addDerived() {
    const label = this.derivedLabelTarget.value.trim()
    const key = this.derivedKeyTarget.value.trim()
    if (!label) { this.derivedLabelTarget.focus(); return }
    if (!key) { this.derivedKeyTarget.focus(); return }
    const row = this.rowElement({ key, label, type: this.derivedTypeTarget.value, derived: true })
    row.classList.add("added")
    this.listTarget.appendChild(row)
    this.derivedLabelTarget.value = ""
    this.derivedKeyTarget.value = ""
    this.edited()
  }

  // ⌄ D20 — show or hide a row's data type, alignment and (derived) key
  toggleDetails(event) {
    const row = event.target.closest("[data-grid-columns-row]")
    const details = row?.querySelector("[data-grid-columns-details]")
    if (!details) return
    details.classList.toggle("d-none")
    row.classList.toggle("open", !details.classList.contains("d-none"))
  }

  // The type chip follows the data type picked in the details
  typeChanged(event) {
    const row = event.target.closest("[data-grid-columns-row]")
    const chip = row?.querySelector("[data-grid-columns-type-chip]")
    if (chip) chip.textContent = event.target.value
    this.edited()
  }

  // Remove a row; its column goes back to the add list
  remove(event) {
    const row = event.target.closest("[data-grid-columns-row]")
    if (!row || row.dataset.locked === "true") return
    row.remove()
    this.syncOptions()
    this.edited()
  }

  // H6 — show the page's standard columns; saving now removes the firm's (or report's) saved columns
  reset(event) {
    event.preventDefault()
    this.listTarget.replaceChildren(this.standardTarget.content.cloneNode(true))
    this.syncOptions()
    this.updateCount()
    this.resetTarget.value = "1"
    this.resetNoteTarget.classList.remove("d-none")
  }

  // Any edit after a reset saves the list as shown instead
  edited() {
    this.resetTarget.value = "0"
    this.resetNoteTarget.classList.add("d-none")
    this.updateCount()
  }

  // ④ On submit: the list as JSON, spinner on, button off (E6 — a double click sends one save)
  serialise(event) {
    const rows = this.rows().filter((row) => row.dataset.locked !== "true").map((row) => {
      const label = row.querySelector("[data-grid-columns-label]").value
      const data = row.dataset.id ? { id: row.dataset.id, label } : { key: row.dataset.key, label }
      // D20 — data type and alignment are sent only when changed, so untouched rows keep what they have
      // (including a type worked out from the database, or a legacy alignment)
      const type = row.querySelector("[data-grid-columns-type]")
      const align = row.querySelector("[data-grid-columns-align]")
      if (type && type.value !== (type.dataset.initial || "")) data.data_type = type.value
      if (align && align.value !== (align.dataset.initial || "")) data.alignment = align.value
      // H18, E24 — a derived field sends its typed key
      if (row.dataset.derived === "true") {
        data.derived = true
        const dkey = row.querySelector("[data-grid-columns-dkey]")
        data.key = dkey ? dkey.value : row.dataset.key
      }
      return data
    })
    this.rowsTarget.value = JSON.stringify(rows)
    markSaving(event.target)
  }

  rows() {
    return Array.from(this.listTarget.querySelectorAll("[data-grid-columns-row]"))
  }

  updateCount() {
    if (!this.hasCountTarget) return
    const n = this.rows().length
    this.countTarget.textContent = `${n} column${n === 1 ? "" : "s"}`
  }

  // Park the options whose column is listed; bring back the others
  syncOptions() {
    const listed = new Set(this.rows().map((row) => clean(row.dataset.key)))
    this.parked.forEach((entry, key) => {
      if (!listed.has(key)) { entry.group.appendChild(entry.option); this.parked.delete(key) }
    })
    this.addTarget.querySelectorAll("option").forEach((option) => {
      const key = clean(option.value)
      if (key && listed.has(key)) {
        this.parked.set(key, { option, group: option.parentElement })
        option.remove()
      }
    })
  }

  // A new row, the same markup as grid_columns/_row: the details reuse the standard template's selects
  rowElement({ key, label, type, derived }) {
    const li = document.createElement("li")
    li.className = "grid-columns-row"
    li.dataset.gridColumnsRow = ""
    li.dataset.key = key
    li.dataset.locked = "false"
    li.dataset.derived = derived ? "true" : "false"
    li.dataset.storedAlignment = ""
    li.draggable = true
    li.innerHTML = `
      <div class="grid-columns-main">
        <i class="ti ti-grip-vertical grid-columns-handle" title="Drag to reorder" aria-hidden="true"></i>
        <div class="grid-columns-name">
          <input type="text" maxlength="100" data-grid-columns-label>
          <div class="grid-columns-key" data-grid-columns-key-text></div>
        </div>
        ${derived ? '<span class="grid-columns-chip" title="A derived field: its key is a path you typed"><i class="ti ti-math-function"></i> Derived</span>' : ""}
        <span class="grid-columns-chip" data-grid-columns-type-chip></span>
        <button type="button" class="grid-columns-icon-btn" data-action="grid-columns-form#toggleDetails" title="Data type and alignment"><i class="ti ti-chevron-down"></i></button>
        <button type="button" class="grid-columns-remove" data-action="grid-columns-form#remove" title="Remove from the list (saved when you click Save)"><i class="ti ti-x"></i></button>
      </div>
      <div class="grid-columns-details d-none" data-grid-columns-details>
        <div class="row g-2">
          <div class="col-6"><label class="form-label small mb-1">Data type</label>
            <select class="form-select form-select-sm" data-grid-columns-type data-action="change->grid-columns-form#typeChanged"></select></div>
          <div class="col-6"><label class="form-label small mb-1">Alignment</label>
            <select class="form-select form-select-sm" data-grid-columns-align>
              <option value="">Default</option><option value="text-start">Left</option>
              <option value="text-center">Centre</option><option value="text-end">Right</option>
            </select></div>
          ${derived ? '<div class="col-12"><label class="form-label small mb-1">Key</label><input type="text" class="form-control form-control-sm" maxlength="255" data-grid-columns-dkey></div>' : ""}
        </div>
      </div>`
    const input = li.querySelector("[data-grid-columns-label]")
    input.value = label || clean(key)
    input.setAttribute("aria-label", `Heading for ${input.value}`)
    li.querySelector("[data-grid-columns-key-text]").textContent = clean(key)
    li.querySelector("[data-grid-columns-type-chip]").textContent = type || "String"
    li.querySelector(".grid-columns-remove").setAttribute("aria-label", `Remove ${input.value}`)
    // Data type choices: the same list the derived field box offers
    const typeSelect = li.querySelector("[data-grid-columns-type]")
    Array.from(this.derivedTypeTarget.options).forEach((option) => {
      const copy = new Option(option.text, option.value, false, option.value === (type || "String"))
      typeSelect.appendChild(copy)
    })
    // A type worked out from the database shows as is (sent only when changed)
    if (type && !Array.from(typeSelect.options).some((o) => o.value === type)) typeSelect.appendChild(new Option(type, type, true, true))
    typeSelect.dataset.initial = derived ? "" : (type || "")
    li.querySelector("[data-grid-columns-align]").dataset.initial = ""
    if (derived) li.querySelector("[data-grid-columns-dkey]").value = key
    return li
  }

  // Drag to reorder; locked rows stay at the top
  bindDrag() {
    this.listTarget.addEventListener("dragstart", (event) => {
      const row = event.target.closest("[data-grid-columns-row]")
      if (!row || row.dataset.locked === "true") { event.preventDefault(); return }
      this.dragged = row
      row.classList.add("dragging")
      event.dataTransfer.effectAllowed = "move"
      event.dataTransfer.setData("text/plain", row.dataset.key || "")
    })
    this.listTarget.addEventListener("dragover", (event) => {
      const target = event.target.closest("[data-grid-columns-row]")
      if (!this.dragged || !target || target.dataset.locked === "true") return
      event.preventDefault()
      this.rows().forEach((row) => row.classList.toggle("drag-over", row === target))
    })
    this.listTarget.addEventListener("drop", (event) => {
      const target = event.target.closest("[data-grid-columns-row]")
      if (!this.dragged || !target || target === this.dragged || target.dataset.locked === "true") return
      event.preventDefault()
      // Dropped on the lower half of a row: after it; upper half: before it
      const box = target.getBoundingClientRect()
      const after = event.clientY > box.top + box.height / 2
      target.parentNode.insertBefore(this.dragged, after ? target.nextSibling : target)
      this.edited()
    })
    this.listTarget.addEventListener("dragend", () => {
      this.rows().forEach((row) => row.classList.remove("dragging", "drag-over"))
      this.dragged = null
    })
  }
}
