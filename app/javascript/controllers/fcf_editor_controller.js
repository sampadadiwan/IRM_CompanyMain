import { Controller } from "@hotwired/stimulus"

// The custom form editor (form_types/_form): the fields listed on the left, grouped by wizard step; one field's
// settings on the right; one Save for all of them.
//
// Only the screen is new. Each field is still a cocoon nested-fields pane holding its real form_custom_fields_attributes
// inputs (form_types/_form_custom_fields). This controller shows one pane at a time and builds the friendlier widgets
// — choice chips, number format, user picker — which write into those real inputs. With JavaScript off nothing here
// runs: every pane shows, stacked, and the form still saves (the .fcf-js / .fcf-nojs classes, form_type_editor.scss).
//
// Nothing is written to a stored value unless the user changes it: opening and saving an untouched form submits
// exactly what the old page did.

// meta_data holds the choices for these types, as "A,B,C" (FormCustomField::OPTION_FIELD_TYPES)
const OPTION_TYPES = ["Select", "Radio", "DataList", "MultiSelect"]
// Types that cannot be a list filter (FormCustomField::UNFILTERABLE_TYPES)
const UNFILTERABLE = ["File", "Header", "GridColumns", "Calculation"]
// show_user_ids is a 50-character column
const USER_IDS_MAX = 50

export default class extends Controller {
  static targets = ["pane", "list", "search", "count", "summary", "empty", "dirty", "discard", "reordered",
                    "leaveModal", "leaveCount"]
  static values = { users: Array, steps: Array }

  // Runs before the pane targets connect (Stimulus connects targets before connect())
  initialize() {
    this.snapshots = new Map() // pane -> its inputs as first rendered (position aside), to count unsaved changes
    this.positionSnapshots = new Map() // pane -> its position as first rendered
    this.newCount = 0
    this.ready = false
  }

  connect() {
    this.form = this.element.closest("form")
    this.headerSnapshot = this.serializeHeader()
    this.element.classList.add("fcf-ready")

    // Any typing or change inside the editor: keep the list, preview and unsaved count in step
    this.onEdit = (event) => this.edited(event)
    this.element.addEventListener("input", this.onEdit)
    this.element.addEventListener("change", this.onEdit)
    this.element.addEventListener("trix-change", this.onEdit)

    // The list is rebuilt often, so its clicks and drags are handled here once
    this.bindList()

    // Enter in the editor's own search boxes must not submit (and so save) the whole form
    this.onKeydown = (event) => {
      if (event.key === "Enter" && event.target.matches("[data-fcf-editor-target~='search'], [data-fcf-user-search]")) event.preventDefault()
    }
    this.element.addEventListener("keydown", this.onKeydown)

    // Leaving with unsaved changes: the browser's own prompt on unload, a modal for in-app (Turbo) links
    this.submitting = false
    this.onSubmit = () => { this.submitting = true }
    this.form?.addEventListener("submit", this.onSubmit)
    this.onBeforeUnload = (event) => {
      if (this.submitting || this.dirtyCount() === 0) return
      event.preventDefault()
      event.returnValue = ""
    }
    window.addEventListener("beforeunload", this.onBeforeUnload)
    this.onBeforeVisit = (event) => this.beforeVisit(event)
    document.addEventListener("turbo:before-visit", this.onBeforeVisit)
    // The leave modal must sit directly in <body>: inside the form card's stacking context Bootstrap's backdrop (added
    // to <body>) covers it and its buttons cannot be clicked. Once moved it is outside this controller, so its
    // button is wired here rather than with data-action
    this.modal = this.leaveModalTarget
    this.modalCount = this.leaveCountTarget
    document.body.appendChild(this.modal)
    this.modal.querySelector("[data-fcf-leave]").addEventListener("click", () => this.leave())
    // Put it back before Turbo caches the page, so a restored copy finds it inside the editor again
    this.onBeforeCache = () => this.element.appendChild(this.modal)
    document.addEventListener("turbo:before-cache", this.onBeforeCache)

    this.ready = true
    this.renderList()
    // Open the first field that failed to save, else the one named in the URL, else the first in the list
    const errored = this.panes().find((pane) => pane.dataset.fcfError === "true")
    const hashed = this.paneByKey(window.location.hash.replace("#field-", ""))
    this.select(errored || hashed || this.orderedPanes()[0])
    this.updateDirty()
  }

  disconnect() {
    this.element.removeEventListener("input", this.onEdit)
    this.element.removeEventListener("change", this.onEdit)
    this.element.removeEventListener("trix-change", this.onEdit)
    this.element.removeEventListener("keydown", this.onKeydown)
    this.form?.removeEventListener("submit", this.onSubmit)
    window.removeEventListener("beforeunload", this.onBeforeUnload)
    document.removeEventListener("turbo:before-visit", this.onBeforeVisit)
    document.removeEventListener("turbo:before-cache", this.onBeforeCache)
    if (this.modal?.parentElement === document.body) this.modal.remove()
  }

  // ── Panes ─────────────────────────────────────────────────────────────────────────────────────────────────

  // Every pane, the rendered ones and those cocoon adds (Add Field)
  paneTargetConnected(pane) {
    // A new pane is a copy of cocoon's template, so it has no id: give it a key of its own
    if (!pane.dataset.fcfKey) pane.dataset.fcfKey = `new-${++this.newCount}`
    this.initWidgets(pane)
    this.applyType(pane)
    this.snapshots.set(pane, this.serialize(pane))
    this.positionSnapshots.set(pane, this.position(pane).value)
    if (!this.ready) return

    // Added with Add Field: last in its step, opened, label focused
    this.position(pane).value = this.maxPosition() + 1
    this.renderList()
    this.select(pane)
    this.input(pane, "[data-fcf-label]")?.focus()
    this.updateDirty()
  }

  paneTargetDisconnected(pane) {
    this.snapshots.delete(pane)
    this.positionSnapshots.delete(pane)
    if (!this.ready) return
    this.renderList()
    this.updateDirty()
  }

  panes() { return this.paneTargets }

  paneByKey(key) { return key ? this.panes().find((pane) => pane.dataset.fcfKey === key) : null }

  paneOf(element) { return element.closest("[data-fcf-editor-target~='pane']") }

  input(pane, selector) { return pane.querySelector(selector) }

  position(pane) { return this.input(pane, "[data-fcf-position]") }

  meta(pane) { return this.input(pane, "[data-fcf-meta]") }

  userIds(pane) { return this.input(pane, "[data-fcf-user-ids]") }

  // A field's facts, read from its inputs
  fieldOf(pane) {
    const typeSelect = this.input(pane, "[data-fcf-type]")
    const name = this.input(pane, "[data-fcf-name]")?.dataset.fcfName || this.input(pane, "[data-fcf-name-input]")?.value || ""
    return {
      key: pane.dataset.fcfKey,
      label: this.input(pane, "[data-fcf-label]").value.trim(),
      name: name.trim(),
      type: typeSelect.value,
      typeLabel: typeSelect.options[typeSelect.selectedIndex]?.text || typeSelect.value,
      step: this.input(pane, "[data-fcf-step]").value,
      position: parseInt(this.position(pane).value, 10),
      required: this.input(pane, "input[type=checkbox][data-fcf-flag='required']").checked,
      readOnly: this.input(pane, "input[type=checkbox][data-fcf-flag='read_only']").checked,
      filter: this.input(pane, "input[type=checkbox][data-fcf-flag='filter']").checked,
      conditional: this.input(pane, "[data-fcf-condition-on]").value !== "",
      someUsers: this.userIds(pane).value.trim() !== "",
      internal: pane.dataset.fcfInternal === "true",
      error: pane.dataset.fcfError === "true",
      isNew: pane.dataset.fcfPersisted !== "true",
      removed: pane.classList.contains("fcf-removed"),
      help: this.input(pane, "[data-fcf-help]").value.trim(),
      meta: this.meta(pane).value
    }
  }

  // ── Selecting a field ─────────────────────────────────────────────────────────────────────────────────────

  select(pane) {
    this.active = pane || null
    this.panes().forEach((each) => each.classList.toggle("active", each === pane))
    this.listTarget.querySelectorAll("[data-fcf-row]").forEach((row) => {
      row.classList.toggle("active", row.dataset.key === pane?.dataset.fcfKey)
    })
    this.emptyTarget.classList.toggle("d-none", this.panes().length > 0)
    if (!pane) return

    // The pane's lists depend on the other fields, which may have changed since it was last open
    this.buildConditionOptions(pane)
    this.buildUserPicker(pane)
    this.renderPreview(pane)
    // Keep Turbo's own history state (null would make Back a full reload)
    history.replaceState(history.state, "", `#field-${pane.dataset.fcfKey}`)
  }

  // ── The list ──────────────────────────────────────────────────────────────────────────────────────────────

  // All panes in form order: by step (as the steps value lists them), then position
  orderedPanes() {
    const stepOrder = this.stepsValue.map(([, key]) => key)
    // Each pane's step and position read once, then sorted (a form can have ~300 fields)
    return this.panes().map((pane, i) => {
      const position = parseInt(this.position(pane).value, 10)
      return { pane, i, step: stepOrder.indexOf(this.input(pane, "[data-fcf-step]").value), position: isNaN(position) ? Infinity : position }
    }).sort((a, b) => (a.step - b.step) || (a.position - b.position) || (a.i - b.i)).map((entry) => entry.pane)
  }

  renderList() {
    const query = this.hasSearchTarget ? this.searchTarget.value.trim().toLowerCase() : ""
    const labels = Object.fromEntries(this.stepsValue.map(([label, key]) => [key, label]))
    const groups = new Map()
    this.orderedPanes().forEach((pane) => {
      const field = this.fieldOf(pane)
      if (!groups.has(field.step)) groups.set(field.step, [])
      groups.get(field.step).push(field)
    })

    let html = ""
    groups.forEach((fields, step) => {
      const shown = fields.filter((f) => !query || f.label.toLowerCase().includes(query) || f.name.toLowerCase().includes(query))
      if (shown.length === 0) return
      html += `<div class="fcf-step-head" data-fcf-step-head="${esc(step)}"><span>${esc(labels[step] || step)}</span>` +
              `<span>${fields.length}</span></div><ul class="grid-columns-list fcf-rows">`
      shown.forEach((f) => { html += this.rowHtml(f) })
      html += "</ul>"
    })
    if (!html) html = `<p class="text-muted small p-3 mb-0">${query ? "No field matches the search." : "No fields yet."}</p>`
    this.listTarget.innerHTML = html

    // Counts above and in the header
    const kept = this.panes().filter((pane) => !pane.classList.contains("fcf-removed"))
    const steps = new Set(kept.map((pane) => this.fieldOf(pane).step))
    this.countTarget.textContent = kept.length
    this.summaryTarget.textContent = `${kept.length} field${kept.length === 1 ? "" : "s"} across ${steps.size} step${steps.size === 1 ? "" : "s"}.`
    this.emptyTarget.classList.toggle("d-none", this.panes().length > 0)
  }

  rowHtml(f) {
    const flag = (on, icon, title, extra = "") => on ? `<i class="ti ${icon} fcf-flag ${extra}" title="${title}"></i>` : ""
    const active = this.active?.dataset.fcfKey === f.key ? "active" : ""
    return `<li class="grid-columns-row fcf-row ${active} ${f.removed ? "removed" : ""}" data-fcf-row data-key="${esc(f.key)}" draggable="true">
      <div class="grid-columns-main">
        <i class="ti ti-grip-vertical grid-columns-handle" title="Drag to reorder" aria-hidden="true"></i>
        <div class="grid-columns-name">
          <div class="fcf-row-label">${f.error ? '<i class="ti ti-point-filled text-danger" title="Could not be saved — see the field"></i>' : ""}${esc(f.label || "New field")}</div>
          <div class="grid-columns-key">${esc(f.name || "—")}</div>
        </div>
        ${f.isNew ? '<span class="grid-columns-chip fcf-chip-new">New</span>' : ""}
        ${f.removed ? '<span class="grid-columns-chip">Removed on save</span>' : ""}
        ${flag(f.required, "ti-asterisk", "Required", "text-danger")}
        ${flag(f.readOnly, "ti-lock", "Read only")}
        ${flag(f.filter, "ti-filter", "Shown in the list's filter")}
        ${flag(f.conditional, "ti-git-branch", "Shown only when a condition matches")}
        ${flag(f.someUsers, "ti-users", "Visible to some users only")}
        ${flag(f.internal, "ti-eye-off", "Internal")}
        <span class="grid-columns-chip">${esc(f.typeLabel)}</span>
      </div>
    </li>`
  }

  search() { this.renderList() }

  bindList() {
    // Click a row: open that field
    this.listTarget.addEventListener("click", (event) => {
      const row = event.target.closest("[data-fcf-row]")
      if (row) this.select(this.paneByKey(row.dataset.key))
    })

    // Drag a row onto another row (before or after it, by the pointer's half) or onto a step heading (top of that step)
    this.listTarget.addEventListener("dragstart", (event) => {
      const row = event.target.closest("[data-fcf-row]")
      if (!row) return
      this.draggedKey = row.dataset.key
      row.classList.add("dragging")
      event.dataTransfer.effectAllowed = "move"
      event.dataTransfer.setData("text/plain", row.dataset.key)
    })
    this.listTarget.addEventListener("dragover", (event) => {
      const target = event.target.closest("[data-fcf-row], [data-fcf-step-head]")
      if (!this.draggedKey || !target) return
      event.preventDefault()
      this.listTarget.querySelectorAll(".drag-over").forEach((el) => el.classList.remove("drag-over"))
      target.classList.add("drag-over")
    })
    this.listTarget.addEventListener("drop", (event) => {
      const target = event.target.closest("[data-fcf-row], [data-fcf-step-head]")
      if (!this.draggedKey || !target) return
      event.preventDefault()
      if (target.dataset.fcfStepHead !== undefined) {
        this.move(this.draggedKey, { step: target.dataset.fcfStepHead })
      } else if (target.dataset.key !== this.draggedKey) {
        const box = target.getBoundingClientRect()
        this.move(this.draggedKey, { key: target.dataset.key, after: event.clientY > box.top + box.height / 2 })
      }
      // move() re-renders the list, so the dragged row is gone before its dragend could clear this
      this.draggedKey = null
    })
    this.listTarget.addEventListener("dragend", () => {
      this.draggedKey = null
      this.renderList()
    })
  }

  // Move a field next to another (taking that field's step) or to the top of a step, then renumber
  move(key, { key: targetKey, after = false, step }) {
    const dragged = this.paneByKey(key)
    const order = this.orderedPanes().filter((pane) => pane !== dragged)
    let index
    if (step) {
      // Top of the step: before its first field (or after the steps listed before it)
      const stepOrder = this.stepsValue.map(([, k]) => k)
      index = order.findIndex((pane) => stepOrder.indexOf(this.fieldOf(pane).step) >= stepOrder.indexOf(step))
      if (index === -1) index = order.length
    } else {
      const target = this.paneByKey(targetKey)
      step = this.fieldOf(target).step
      index = order.indexOf(target) + (after ? 1 : 0)
    }
    order.splice(index, 0, dragged)
    this.input(dragged, "[data-fcf-step]").value = step
    // Only the step it lands in is renumbered. Single-page forms show every field by position whatever its step, so
    // renumbering the whole list would also move fields in other steps on those forms
    this.renumber(order.filter((pane) => this.input(pane, "[data-fcf-step]").value === step))
    this.renderList()
    this.select(dragged)
    this.updateDirty()
  }

  // The step's fields (with the moved one) take the positions they already held, in the new order. Every other field —
  // in other steps, or not shown on this page (calculations, internal fields) — keeps its number. The controller saves these exact numbers
  // (reordered=1 → acts_as_list leaves them alone).
  renumber(order) {
    const slots = order.map((pane) => parseInt(this.position(pane).value, 10)).filter((n) => !isNaN(n)).sort((a, b) => a - b)
    let previous = 0
    order.forEach((pane, i) => {
      // Strictly increasing: duplicates or missing numbers (very old fields) get the next free number
      const slot = Math.max(slots[i] ?? previous + 1, previous + 1)
      this.position(pane).value = slot
      previous = slot
    })
    this.reorderedTarget.value = "1"
  }

  maxPosition() {
    return this.panes().reduce((max, pane) => Math.max(max, parseInt(this.position(pane).value, 10) || 0), 0)
  }

  // ── Editing ───────────────────────────────────────────────────────────────────────────────────────────────

  edited(event) {
    const pane = this.paneOf(event.target)
    if (pane) {
      // Label: the pane's title, and (for a new field) the stored name derived from it until it is typed by hand
      if (event.target.matches("[data-fcf-label]")) {
        this.input(pane, "[data-fcf-title]").textContent = event.target.value.trim() || "New field"
        const name = this.input(pane, "[data-fcf-name-input]")
        if (name && !name.dataset.touched) name.value = toName(event.target.value)
      }
      if (event.target.matches("[data-fcf-name-input]") && event.type === "input") event.target.dataset.touched = "1"
      // The raw meta_data box: re-read it into the widgets
      if (event.target.matches("[data-fcf-meta]")) {
        this.initWidgets(pane)
        this.applyType(pane)
      }
      if (event.target.matches("[data-fcf-condition-value]") || event.target.matches("[data-fcf-condition-on]")) {
        this.updateConditionDatalist(pane)
      }
      this.renderPreview(pane)
      this.renderListSoon()
    }
    this.updateDirty()
  }

  // Typing rebuilds the list at most once a frame
  renderListSoon() {
    if (this.listFrame) return
    this.listFrame = requestAnimationFrame(() => {
      this.listFrame = null
      this.renderList()
    })
  }

  typeChanged(event) {
    const pane = this.paneOf(event.target)
    this.initWidgets(pane)
    this.applyType(pane)
    this.renderPreview(pane)
  }

  stepChanged() { this.renderList() }

  // Required and Read only cannot both be on (FormCustomField#read_only_and_required): turning one on turns the other off
  flagChanged(event) {
    const pane = this.paneOf(event.target)
    const flag = event.target.dataset.fcfFlag
    const note = this.input(pane, "[data-fcf-flag-note]")
    note.classList.add("d-none")
    if (!event.target.checked || !["required", "read_only"].includes(flag)) return
    const other = this.input(pane, `input[type=checkbox][data-fcf-flag='${flag === "required" ? "read_only" : "required"}']`)
    if (other.checked) {
      other.checked = false
      note.classList.remove("d-none")
    }
  }

  toggleChecks(event) {
    const pane = this.paneOf(event.target)
    this.input(pane, "[data-fcf-checks]").classList.toggle("open")
  }

  toggleInfo(event) {
    const pane = this.paneOf(event.target)
    this.input(pane, "[data-fcf-info]").classList.toggle("open")
  }

  // Remove: a saved field is marked (_destroy) and can be undone until Save; a new one is simply taken out
  toggleRemove(event) {
    const pane = this.paneOf(event.target)
    if (pane.dataset.fcfPersisted !== "true") {
      const order = this.orderedPanes()
      const next = order[order.indexOf(pane) + 1] || order[order.indexOf(pane) - 1]
      pane.remove()
      this.select(next)
      return
    }
    const destroy = this.input(pane, "[data-fcf-destroy]")
    const removing = !pane.classList.contains("fcf-removed")
    destroy.value = removing ? "1" : "false"
    pane.classList.toggle("fcf-removed", removing)
    this.input(pane, "[data-fcf-removed-note]").classList.toggle("d-none", !removing)
    this.input(pane, "[data-fcf-remove]").classList.toggle("d-none", removing)
    this.renderList()
    this.updateDirty()
  }

  // ── Options (meta_data) by type ───────────────────────────────────────────────────────────────────────────

  // Read the stored value into the widget that fits the type. A value the widget cannot represent exactly keeps the
  // raw box open, so it is never rewritten behind the user's back.
  initWidgets(pane) {
    const type = this.input(pane, "[data-fcf-type]").value
    const value = this.meta(pane).value
    pane.dataset.fcfRawNeeded = "false"

    if (OPTION_TYPES.includes(type)) {
      // Ruby's split(",") keeps a leading blank (start with nothing picked) and drops trailing ones
      const parts = value.split(",").map((s) => s.trim())
      while (parts.length && parts[parts.length - 1] === "") parts.pop()
      const blankFirst = parts[0] === "" && parts.length > 0
      const choices = blankFirst ? parts.slice(1) : parts
      if (choices.some((c) => c === "")) pane.dataset.fcfRawNeeded = "true"
      pane.fcfChoices = choices.filter((c) => c !== "")
      this.input(pane, "[data-fcf-blank-first]").checked = blankFirst
      this.renderChips(pane)
    } else if (type === "NumberField") {
      // "precision,separator" (FormCustomField#number_format); blank = shown as typed
      const match = value.trim().match(/^(\d+)\s*(?:,\s*(comma|none)?)?\s*$/)
      if (value.trim() !== "" && !match) pane.dataset.fcfRawNeeded = "true"
      this.input(pane, "[data-fcf-number-precision]").value = match ? match[1] : ""
      this.input(pane, "[data-fcf-number-separator]").value = match?.[2] || "comma"
    }
  }

  // Show the options widget, raw box, title and hint that fit the type
  applyType(pane) {
    const type = this.input(pane, "[data-fcf-type]").value
    const typeSelect = this.input(pane, "[data-fcf-type]")
    const meta = this.meta(pane)
    const hasValue = meta.value.trim() !== ""
    const show = (selector, on) => this.input(pane, selector).classList.toggle("d-none", !on)

    // [title, hint, raw label, raw help, raw shown?, widget]
    let spec
    if (OPTION_TYPES.includes(type)) {
      spec = ["Choices", "The options people pick from, in this order.", "Choices as text", "Separated by commas. A leading comma starts the dropdown with nothing picked.", false, "choices"]
    } else if (type === "NumberField") {
      spec = ["Number format", "How the number is shown on pages.", "Format as text", '"precision,separator", e.g. "2,comma" or "0,none".', false, "number"]
    } else if (type === "Money") {
      spec = ["Currency", "Money is shown in the record's own currency unless you pick one here.", "Currency", "An ISO code such as USD. Leave blank for the record's currency.", true, null]
    } else if (type === "File") {
      spec = ["File tags", "Optional tags read by CapHive features.", "Tags", 'e.g. "skill: true, sector: D2C".', true, null]
    } else if (type === "Calculation") {
      spec = ["Formula", "Worked out from other fields; CapHive support only.", "Formula", "A Ruby expression.", true, null]
    } else {
      spec = ["Options", hasValue ? "This type does not use extra options; the value stored is shown below." : "This type has no extra options.", "Meta data", "Stored as typed.", hasValue, null]
    }
    const [title, hint, rawLabel, rawHelp, rawShown, widget] = spec

    this.input(pane, "[data-fcf-options-title]").textContent = title
    this.input(pane, "[data-fcf-options-sub]").textContent = hint
    this.input(pane, "[data-fcf-meta-label]").textContent = rawLabel
    this.input(pane, "[data-fcf-meta-help]").textContent = rawHelp
    show("[data-fcf-widget='choices']", widget === "choices")
    show("[data-fcf-widget='number']", widget === "number")
    // Money: currency suggestions; any other type: none
    if (type === "Money") {
      meta.setAttribute("list", "fcf_currency_list")
      meta.placeholder = "Record's currency"
    } else {
      meta.removeAttribute("list")
      meta.placeholder = ""
    }
    // The raw box: shown for types edited as typed, when the widget cannot read the value, or when asked for
    const rawOpen = rawShown || pane.dataset.fcfRawNeeded === "true" || pane.dataset.fcfRawOpen === "true"
    show("[data-fcf-meta-raw]", rawOpen)
    const toggle = this.input(pane, "[data-fcf-raw-toggle]")
    toggle.classList.toggle("d-none", rawShown || pane.dataset.fcfRawNeeded === "true")
    toggle.textContent = rawOpen ? "Hide text" : "Edit as text"

    // Show in filter: not for types that cannot be filtered
    const filter = this.input(pane, "input[type=checkbox][data-fcf-flag='filter']")
    const unfilterable = UNFILTERABLE.includes(type)
    if (unfilterable) filter.checked = false
    filter.disabled = unfilterable
    this.input(pane, "[data-fcf-filter-help]").textContent = unfilterable ? "This type can't be used as a filter." : "Appears in the list page's filter panel."

    // The pane header's chip
    this.input(pane, "[data-fcf-type-chip]").textContent = typeSelect.options[typeSelect.selectedIndex]?.text || type

    // Validation rules and more information start open when they hold something
    const rules = [...pane.querySelectorAll("[data-fcf-checks] input, [data-fcf-checks] select")]
      .some((el) => (el.type === "checkbox" ? el.checked : el.type !== "hidden" && el.value !== ""))
    if (rules) this.input(pane, "[data-fcf-checks]").classList.add("open")
    const info = pane.querySelector("[data-fcf-info] input[type=hidden]")
    if (info && info.value.trim() !== "") this.input(pane, "[data-fcf-info]").classList.add("open")
  }

  toggleRaw(event) {
    const pane = this.paneOf(event.target)
    pane.dataset.fcfRawOpen = pane.dataset.fcfRawOpen === "true" ? "false" : "true"
    this.applyType(pane)
  }

  renderChips(pane) {
    const box = this.input(pane, "[data-fcf-chips]")
    box.innerHTML = (pane.fcfChoices || []).map((choice, i) =>
      `<span class="fcf-chip">${esc(choice)}<button type="button" class="fcf-chip-x" data-index="${i}" aria-label="Remove ${esc(choice)}"><i class="ti ti-x"></i></button></span>`
    ).join("") || '<span class="text-muted small">No choices yet.</span>'
    box.querySelectorAll(".fcf-chip-x").forEach((button) => {
      button.addEventListener("click", () => {
        pane.fcfChoices.splice(parseInt(button.dataset.index, 10), 1)
        this.writeChoices(pane)
      })
    })
  }

  // Enter or a comma adds what was typed (Enter must not submit the form)
  chipKeydown(event) {
    if (event.key !== "Enter" && event.key !== ",") return
    event.preventDefault()
    this.addChips(event.target)
  }

  chipBlur(event) { this.addChips(event.target) }

  addChips(input) {
    const pane = this.paneOf(input)
    const added = input.value.split(",").map((s) => s.trim()).filter((s) => s !== "")
    input.value = ""
    if (added.length === 0) return
    pane.fcfChoices = [...(pane.fcfChoices || []), ...added.filter((c) => !(pane.fcfChoices || []).includes(c))]
    this.writeChoices(pane)
  }

  choicesChanged(event) { this.writeChoices(this.paneOf(event.target)) }

  // Choices back into meta_data, "A,B,C" — or ",A,B,C" to start with nothing picked
  writeChoices(pane) {
    const blankFirst = this.input(pane, "[data-fcf-blank-first]").checked
    this.meta(pane).value = (blankFirst ? "," : "") + (pane.fcfChoices || []).join(",")
    this.renderChips(pane)
    this.meta(pane).dispatchEvent(new Event("input", { bubbles: true }))
  }

  // Number format back into meta_data: "2,comma"; "As typed" = blank
  numberChanged(event) {
    const pane = this.paneOf(event.target)
    const precision = this.input(pane, "[data-fcf-number-precision]").value
    const separator = this.input(pane, "[data-fcf-number-separator]").value
    this.meta(pane).value = precision === "" ? "" : `${precision},${separator}`
    this.meta(pane).dispatchEvent(new Event("input", { bubbles: true }))
  }

  // ── When it shows ─────────────────────────────────────────────────────────────────────────────────────────

  // "Only when [field]": the standard fields allowed for this record type and every other field on the form,
  // including ones added but not saved yet. The current value stays even if it matches nothing.
  buildConditionOptions(pane) {
    const select = this.input(pane, "[data-fcf-condition-on]")
    const current = select.value
    const own = this.fieldOf(pane).name
    // The server's list (FormTypeEditorHelper#fcf_condition_options) also holds fields this page hides, e.g.
    // calculations — keep it, and add the fields added here but not saved yet
    pane.fcfServerConditions ||= [...select.options].map((option) => [option.text, option.value])
    const options = [...pane.fcfServerConditions]
    this.orderedPanes().filter((p) => p !== pane && !p.classList.contains("fcf-removed")).map((p) => this.fieldOf(p))
      .filter((f) => f.name && f.name !== own && !options.some(([, name]) => name === f.name))
      .forEach((f) => options.push([f.label || f.name, f.name]))
    if (current && !options.some(([, name]) => name === current)) options.push([`${current} (not a field on this form)`, current])
    select.innerHTML = options.map(([label, name]) => `<option value="${esc(name)}">${esc(label)}</option>`).join("")
    select.value = current
    this.updateConditionDatalist(pane)
  }

  conditionChanged(event) { this.updateConditionDatalist(this.paneOf(event.target)) }

  // The value box suggests the chosen field's choices, and is dimmed while the field shows always
  updateConditionDatalist(pane) {
    const on = this.input(pane, "[data-fcf-condition-on]").value
    pane.querySelectorAll("[data-fcf-condition-part]").forEach((el) => el.classList.toggle("fcf-dim", on === ""))
    const value = this.input(pane, "[data-fcf-condition-value]")
    const parent = this.panes().find((p) => this.fieldOf(p).name === on)
    const choices = parent && OPTION_TYPES.includes(this.fieldOf(parent).type) ? (parent.fcfChoices || []) : []
    let list = pane.querySelector("datalist[data-fcf-condition-list]")
    if (!list) {
      list = document.createElement("datalist")
      list.dataset.fcfConditionList = ""
      list.id = `fcf_condition_list_${pane.dataset.fcfKey}`
      pane.appendChild(list)
    }
    list.innerHTML = choices.map((c) => `<option value="${esc(c)}"></option>`).join("")
    value.setAttribute("list", list.id)
  }

  // "Visible to": Everyone, or a picked list of the firm's users written to show_user_ids as "12,34"
  buildUserPicker(pane) {
    const ids = this.userIds(pane).value.split(",").map((s) => s.trim()).filter((s) => s !== "")
    this.input(pane, "[data-fcf-visible-mode]").value = ids.length ? "some" : "all"
    this.renderUserPicker(pane)
  }

  visibleModeChanged(event) {
    const pane = this.paneOf(event.target)
    if (event.target.value === "all") {
      this.userIds(pane).value = ""
      this.userIds(pane).dispatchEvent(new Event("input", { bubbles: true }))
    }
    this.renderUserPicker(pane)
  }

  renderUserPicker(pane) {
    const box = this.input(pane, "[data-fcf-user-picker]")
    const some = this.input(pane, "[data-fcf-visible-mode]").value === "some"
    box.classList.toggle("d-none", !some)
    if (!some) return

    const ids = this.userIds(pane).value.split(",").map((s) => s.trim()).filter((s) => s !== "")
    const names = new Map(this.usersValue.map(([id, label]) => [String(id), label]))
    const query = (box.querySelector("[data-fcf-user-search]")?.value || "").toLowerCase()
    const chips = ids.map((id) => `<span class="fcf-chip">${esc(names.get(id) || `User #${id}`)}<button type="button" class="fcf-chip-x" data-user="${esc(id)}" aria-label="Remove"><i class="ti ti-x"></i></button></span>`).join("")
    const rows = this.usersValue.filter(([, label]) => !query || label.toLowerCase().includes(query)).slice(0, 200)
      .map(([id, label]) => `<label class="form-check small mb-1"><input type="checkbox" class="form-check-input" data-user="${id}" ${ids.includes(String(id)) ? "checked" : ""}> <span class="form-check-label">${esc(label)}</span></label>`).join("")

    box.innerHTML = `
      <div class="mb-2">${chips || '<span class="small text-muted">No one picked yet — until someone is, the field stays visible to everyone.</span>'}</div>
      <input type="search" class="form-control form-control-sm mb-2" placeholder="Search users…" data-fcf-user-search value="${esc(query)}" aria-label="Search users">
      <div class="fcf-user-list">${rows || '<span class="small text-muted">No user matches.</span>'}</div>
      <div class="small text-danger d-none" data-fcf-user-limit>That's the most this setting holds (${USER_IDS_MAX} characters of user ids — about 8 users).</div>`

    box.querySelector("[data-fcf-user-search]").addEventListener("input", () => {
      this.renderUserPicker(pane)
      const search = box.querySelector("[data-fcf-user-search]")
      search.focus()
      search.setSelectionRange(search.value.length, search.value.length)
    })
    box.querySelectorAll("input[type=checkbox][data-user], .fcf-chip-x[data-user]").forEach((el) => {
      el.addEventListener(el.matches("input") ? "change" : "click", (event) => {
        // event is from the picker, not a real input: stop the editor's own change handling counting it twice
        event.stopPropagation()
        const id = el.dataset.user
        const adding = el.matches("input") && el.checked
        const next = adding ? [...ids, id] : ids.filter((each) => each !== id)
        if (next.join(",").length > USER_IDS_MAX) {
          el.checked = false
          box.querySelector("[data-fcf-user-limit]").classList.remove("d-none")
          return
        }
        this.userIds(pane).value = next.join(",")
        this.userIds(pane).dispatchEvent(new Event("input", { bubbles: true }))
        this.renderUserPicker(pane)
      })
    })
  }

  // ── Preview ───────────────────────────────────────────────────────────────────────────────────────────────

  // An approximation of the field on the record's form, from what is typed now
  renderPreview(pane) {
    const box = this.input(pane, "[data-fcf-preview]")
    if (!box) return
    const f = this.fieldOf(pane)
    const label = `<label class="form-label">${esc(f.label || "New field")}${f.required ? ' <span class="text-danger">*</span>' : ""}</label>`
    const disabled = f.readOnly ? "disabled" : ""
    const choices = pane.fcfChoices || []
    const blankFirst = this.input(pane, "[data-fcf-blank-first]").checked
    let control
    switch (f.type) {
      case "TextArea":
        control = `<textarea class="form-control" rows="3" ${disabled}></textarea>`; break
      case "NumberField":
        control = `<input class="form-control" placeholder="${esc(numberSample(f.meta))}" ${disabled}>`; break
      case "Money":
        control = `<div class="input-group"><span class="input-group-text">${esc(f.meta.trim() || "Record's currency")}</span><input class="form-control" placeholder="0.00" ${disabled}></div>`; break
      case "DateField":
        control = `<input type="date" class="form-control" ${disabled}>`; break
      case "Select":
      case "DataList":
        control = `<select class="form-select" ${disabled}>${blankFirst ? "<option></option>" : ""}${choices.map((c) => `<option>${esc(c)}</option>`).join("")}</select>`; break
      case "Radio":
        control = choices.map((c) => `<div class="form-check"><input class="form-check-input" type="radio" name="fcf_preview_${esc(f.key)}" ${disabled}><label class="form-check-label">${esc(c)}</label></div>`).join("") || '<div class="small text-muted">Add choices to see them here.</div>'; break
      case "MultiSelect":
        control = choices.map((c) => `<div class="form-check"><input class="form-check-input" type="checkbox" ${disabled}><label class="form-check-label">${esc(c)}</label></div>`).join("") || '<div class="small text-muted">Add choices to see them here.</div>'; break
      case "CheckBox":
        control = `<div class="form-check"><input class="form-check-input" type="checkbox" ${disabled}><label class="form-check-label">Yes</label></div>`; break
      case "File":
        control = `<input type="file" class="form-control" ${disabled}>`; break
      case "Header":
        box.innerHTML = `<h6 class="mb-0">${esc(f.label || "New section")}</h6>${f.help ? `<div class="form-text">${esc(f.help)}</div>` : ""}`
        return
      case "Calculation":
      case "GridColumns":
        control = '<div class="small text-muted">Worked out automatically — not typed in.</div>'; break
      default:
        control = `<input class="form-control" ${disabled}>`
    }
    const notes = [
      f.readOnly ? "Read only: shown, but can't be changed." : null,
      f.conditional ? "Appears only when its condition matches." : null,
      f.someUsers ? "Only the picked users see it." : null
    ].filter(Boolean).map((n) => `<div class="small text-muted mt-1"><i class="ti ti-info-circle me-1"></i>${n}</div>`).join("")
    box.innerHTML = `${label}${control}${f.help ? `<div class="form-text">${esc(f.help)}</div>` : ""}${notes}`
  }

  // ── Unsaved changes ───────────────────────────────────────────────────────────────────────────────────────

  // A pane's submitted inputs as one string; widgets have no name, so only stored values count. Position is left out:
  // one drag renumbers several fields, and is counted once (dirtyCount)
  serialize(root) {
    return [...root.querySelectorAll("input[name], select[name], textarea[name]")]
      .filter((el) => !el.name.endsWith("[position]"))
      .map((el) => `${el.name}=${el.type === "checkbox" || el.type === "radio" ? el.checked : el.value}`)
      .join("&")
  }

  // The form's own inputs above the fields: Form for, Tag (and the debug-only regulatory env)
  serializeHeader() {
    return ["form_type[name]", "form_type[tag]", "form_type[reg_env]"]
      .map((name) => this.form?.querySelector(`[name='${name}']`)?.value ?? "").join("&")
  }

  dirtyCount() {
    let count = this.serializeHeader() !== this.headerSnapshot ? 1 : 0
    let reordered = false
    this.panes().forEach((pane) => {
      // A new field is a change; so is any edited one
      if (pane.dataset.fcfPersisted !== "true" || this.serialize(pane) !== this.snapshots.get(pane)) count += 1
      if (pane.dataset.fcfPersisted === "true" && this.position(pane).value !== this.positionSnapshots.get(pane)) reordered = true
    })
    // A new order is one change, however many fields it renumbered
    return count + (reordered ? 1 : 0)
  }

  updateDirty() {
    const count = this.dirtyCount()
    this.dirtyTarget.innerHTML = count ? `<i class="ti ti-point-filled"></i>${count} unsaved change${count === 1 ? "" : "s"}` : ""
    this.discardTarget.classList.toggle("d-none", count === 0)
  }

  // An in-app link while changes are unsaved: ask first
  beforeVisit(event) {
    if (this.submitting || this.dirtyCount() === 0) return
    event.preventDefault()
    this.pendingUrl = event.detail.url
    const count = this.dirtyCount()
    this.modalCount.textContent = count === 1 ? "Your 1 unsaved change will be" : `Your ${count} unsaved changes will be`
    window.bootstrap.Modal.getOrCreateInstance(this.modal).show()
  }

  leave() {
    this.submitting = true
    window.bootstrap.Modal.getOrCreateInstance(this.modal).hide()
    if (this.pendingUrl) window.Turbo.visit(this.pendingUrl)
  }

  // Discard: reload the saved form, without the leave prompt
  discard() { this.submitting = true }
}

// ── Helpers ─────────────────────────────────────────────────────────────────────────────────────────────────

function esc(value) {
  return String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))
}

// The stored name a new field gets from its label; the server normalises it the same way (FormCustomField.to_name)
function toName(label) {
  return label.trim().replace(/\s+/g, "_").toLowerCase().replace(/[^0-9a-z_]/g, "").replace(/_+/g, "_")
}

// 1234567.891 shown with the number format "2,comma" → "1,234,567.89"
function numberSample(meta) {
  const match = (meta || "").trim().match(/^(\d+)\s*(?:,\s*(comma|none)?)?\s*$/)
  if (!match) return "1234567.891"
  const precision = parseInt(match[1], 10)
  const fixed = (1234567.891).toFixed(precision)
  return match[2] === "none" ? fixed : fixed.replace(/\B(?=(\d{3})+(?!\d))/g, (m, offset, s) => (s.indexOf(".") === -1 || offset < s.indexOf(".") ? "," : ""))
}
