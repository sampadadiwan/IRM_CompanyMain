import { Controller } from "@hotwired/stimulus"
import { initSelect2 } from "custom/select2_handler"

export default class extends Controller {
  static targets = [
    "nameDisplay", "nameInput",
    "previewFrame",
    "sortKey", "sortDir",
    "filtersPanel", "rootFilterRows", "childFilterRows",
    "formulaInput", "formulaPreview", "formulaSubmit", "formulaColumns",
    "scheduleFrequency", "scheduleRecipients", "scheduleTimezone",
    "groupRowsBy", "currency",
    "settings"
  ]

  static values = {
    aggregateUrl: String,
    sortUrl:      String,
    nameUrl:      String,
    templateUrl:  String,
    previewUrl:   String,
    validateFormulaUrl: String,
    joinSettingsUrl: String,
    csrf:         String,
  }

  // Remember every control's saved value, so a failed save can put it back
  // (honest save feedback — worked examples H22, E25, X3)
  connect() {
    this._rememberAll()
    // Builder updates replace the settings panel by Turbo Stream (H2): remember
    // the new controls' saved values once each stream has rendered
    this._onStreamRender = (event) => {
      const render = event.detail.render
      event.detail.render = async (streamElement) => {
        await render(streamElement)
        this._rememberAll()
      }
    }
    document.addEventListener("turbo:before-stream-render", this._onStreamRender)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this._onStreamRender)
  }

  _rememberAll() {
    this.element.querySelectorAll("select, input[type=checkbox]").forEach(el => this._remember(el))
  }

  // The settings panel is replaced by a Turbo stream after every change, which the global select2 setup
  // (page and frame loads only) doesn't see — set up its select2 lists (the pivot's categories) each time
  settingsTargetConnected(element) {
    initSelect2(element)
  }

  // Keeps the open settings tab across re-renders (read by builder_active_tab)
  rememberTab(e) {
    document.cookie = `rb_tab=${encodeURIComponent(e.currentTarget.dataset.tab)}; path=/report_builder; SameSite=Lax`
  }

  // Opens a settings tab from elsewhere, e.g. a formula column's "Edit in Formulas"
  openTab(e) {
    this.element.querySelector(`#rb-tab-${e.currentTarget.dataset.tab}`)?.click()
  }

  startRename() {
    this.nameDisplayTarget.classList.add("d-none")
    this.nameInputTarget.classList.remove("d-none")
    this.nameInputTarget.focus()
    this.nameInputTarget.select()
  }

  commitRename(e) {
    if (e.type === "keydown" && e.key !== "Enter") return
    const name = this.nameInputTarget.value.trim() || "Untitled Report"
    this.nameDisplayTarget.textContent = name
    this.nameDisplayTarget.classList.remove("d-none")
    this.nameInputTarget.classList.add("d-none")
    this._save(this.nameUrlValue, { name }, "Name")
  }

  cancelRename() {
    this.nameInputTarget.value = this.nameDisplayTarget.textContent
    this.nameDisplayTarget.classList.remove("d-none")
    this.nameInputTarget.classList.add("d-none")
  }

  // ── Aggregate selector ────────────────────────────────────────────────

  aggregateChanged(e) {
    const key = e.target.dataset.key
    const agg = e.target.value
    this._save(this.aggregateUrlValue, { key, aggregate: agg }, "Total", [e.target])
  }

  // ── Sort ──────────────────────────────────────────────────────────────

  sortChanged() {
    const sortKey = this.sortKeyTarget.value
    const sortDir = this.sortDirTarget.value
    this._save(this.sortUrlValue, { sort_key: sortKey, sort_dir: sortDir }, "Sort", [this.sortKeyTarget, this.sortDirTarget])
  }

  groupingChanged() {
    const groupRowsBy = this.groupRowsByTarget.value
    this._save(this.templateUrlValue, { template: { group_rows_by: groupRowsBy } }, "Grouping", [this.groupRowsByTarget])
  }

  // Display-only — no conversion happens. Only affects how monetized columns
  // are labeled/formatted in the view, preview, and XLSX export (see
  // ReportBuilderConfig#currency_symbol / #monetized?).
  currencyChanged() {
    const currency = this.currencyTarget.value
    this._save(this.templateUrlValue, { template: { currency: currency } }, "Currency", [this.currencyTarget])
  }

  loadPreview() {
    const frame = this.element.querySelector("turbo-frame#report_builder_preview")
    if (!frame) return

    const url = this.previewUrlValue
    if (!url) return

    // Setting the src triggers Turbo to fetch the frame content
    frame.src = url
  }

  // ── Join select – populate hidden fields before form submit ──────────

  joinSelectChanged(e) {
    const select = e.target
    const form   = select.closest("form")
    if (!select.value) {
      form.querySelector("[name=relation]").value = ""
      this._resetJoinDropdown(select)
      return
    }
    try {
      const assoc = JSON.parse(select.value)
      const currentPath = select.dataset.currentPath || ""
      const fullPath = currentPath ? `${currentPath}.${assoc.name}` : assoc.name
      
      form.querySelector("[name=relation]").value = fullPath
      form.querySelector("[name=model]").value    = assoc.model       || ""
      form.querySelector("[name=fk]").value       = assoc.foreign_key || ""

      if (assoc.has_children) {
        this._showDrillDownButton(select, assoc)
      } else {
        this._hideDrillDownButton(select)
      }
    } catch (_) { /* ignore parse errors */ }
  }

  drillDown(e) {
    const select = this.element.querySelector("select[name=relation_json]")
    const assoc = JSON.parse(select.value)
    const currentPath = select.dataset.currentPath || ""
    const newPath = currentPath ? `${currentPath}.${assoc.name}` : assoc.name
    
    const url = `/report_builder/associations?model=${assoc.model}`
    fetch(url)
      .then(r => r.json())
      .then(data => {
        select.dataset.currentPath = newPath
        this._updateJoinDropdown(select, data, newPath)
        this._hideDrillDownButton(select)
      })
  }

  resetDrillDown(e) {
    const select = this.element.querySelector("select[name=relation_json]")
    const rootModel = this.element.querySelector(".badge.bg-primary-subtle").textContent.trim()
    
    const url = `/report_builder/associations?model=${rootModel}`
    fetch(url)
      .then(r => r.json())
      .then(data => {
        delete select.dataset.currentPath
        this._updateJoinDropdown(select, data, "")
        this._hideDrillDownButton(select)
      })
  }

  _updateJoinDropdown(select, associations, path) {
    const prefix = path ? `${path} › ` : ""
    let html = `<option value="">${path ? "‹ Back to root" : "+ Add new relation…"}</option>`
    
    if (path) {
      html = `<option value="RESET">‹ Back to root</option>`
      html += `<option value="" disabled>Current: ${path}</option>`
    }

    associations.forEach(assoc => {
      const label = `${assoc.label} (${assoc.macro})${assoc.has_children ? " ›" : ""}`
      html += `<option value='${JSON.stringify(assoc)}'>${label}</option>`
    })
    select.innerHTML = html
    
    if (path) {
      select.addEventListener("change", (e) => {
        if (e.target.value === "RESET") {
          this.resetDrillDown()
        }
      }, { once: true })
    }
  }

  _showDrillDownButton(select, assoc) {
    let btn = select.parentElement.querySelector(".drill-down-btn")
    if (!btn) {
      btn = document.createElement("button")
      btn.type = "button"
      btn.className = "btn btn-outline-primary btn-sm drill-down-btn ms-2"
      btn.innerHTML = '<i class="ti ti-chevron-right"></i> Drill Down'
      btn.dataset.action = "click->report-builder#drillDown"
      select.parentElement.appendChild(btn)
    }
    btn.classList.remove("d-none")
  }

  _hideDrillDownButton(select) {
    const btn = select.parentElement.querySelector(".drill-down-btn")
    if (btn) btn.classList.add("d-none")
  }

  _resetJoinDropdown(select) {
    this._hideDrillDownButton(select)
  }

  // ── Formulas ──────────────────────────────────────────────────────────

  // The report's columns as buttons in the formula editor, read from the
  // Columns tab when the editor opens (positions of formulas and pivots skipped) — H9
  fillFormulaColumns() {
    if (!this.hasFormulaColumnsTarget) return
    const rows = this.element.querySelectorAll("tr.column[data-key]")
    const buttons = Array.from(rows)
      .filter(row => !/^(formula|pivot):/.test(row.dataset.key))
      .map(row => {
        const key = row.dataset.key.split(";")[0].trim()
        return `<button type="button" class="btn btn-sm btn-outline-secondary" data-key="${this._esc(key)}"
                        data-action="click->report-builder#insertFormulaColumn">${this._esc(row.dataset.label)}</button>`
      })
    this.formulaColumnsTarget.innerHTML = buttons.join("") || '<span class="text-muted small">Add columns first.</span>'
  }

  // Inserts [key] at the cursor and re-checks the formula
  insertFormulaColumn(e) {
    const input = this.formulaInputTarget
    const token = `[${e.currentTarget.dataset.key}]`
    const start = input.selectionStart ?? input.value.length
    const end = input.selectionEnd ?? input.value.length
    input.value = input.value.slice(0, start) + token + input.value.slice(end)
    input.focus()
    input.selectionStart = input.selectionEnd = start + token.length
    this.validateFormula()
  }

  // Checks the formula as you type and shows its result on the first rows (H10, E11)
  validateFormula() {
    const expression = this.formulaInputTarget.value.trim()
    const preview    = this.formulaPreviewTarget
    const submit     = this.formulaSubmitTarget

    if (!expression) {
      preview.innerHTML = '<span class="text-muted">Enter an expression to see the result.</span>'
      submit.disabled = true
      return
    }

    clearTimeout(this.validateTimeout)
    this.validateTimeout = setTimeout(() => {
      fetch(this.validateFormulaUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfValue,
          "Accept":       "application/json",
        },
        body: JSON.stringify({ expression })
      })
      .then(r => r.json())
      .then(data => {
        if (data.ok) {
          const rows = (data.samples || []).map(s =>
            `<tr><td>${this._esc(s.row)}</td><td class="text-end">${this._esc(s.value)}</td></tr>`).join("")
          preview.innerHTML = rows
            ? `<table class="table table-sm mb-0"><tbody>${rows}</tbody></table>`
            : '<span class="text-success"><i class="ti ti-check me-1"></i> The formula works</span>'
          submit.disabled = false
        } else {
          preview.innerHTML = `<span class="text-danger"><i class="ti ti-alert-circle me-1"></i> ${this._esc(data.error)}</span>`
          submit.disabled = true
        }
      })
    }, 300)
  }

  // ── Filters ───────────────────────────────────────────────────────────
  // Rows are drawn on the server (_filter_row) so each field gets its own input;
  // adding a row or changing its field / operator fetches the row again. Any
  // value change saves all filters after a short pause, once every row is
  // complete (H7, H8, E9, E10).

  addFilterRow(e) {
    const btn = e.currentTarget
    const container = this._filterContainer(btn.dataset.relation)
    if (!container) return
    this._fetchFilterRow(container.dataset.rowUrl, {}).then(html => {
      container.insertAdjacentHTML("beforeend", html)
    })
  }

  filterFieldChanged(e) {
    const row = e.currentTarget.closest(".filter-row")
    // The new row says at once what it still needs (E9); a complete set saves
    this._redrawFilterRow(row, { field: e.currentTarget.value }).then(() => this._scheduleFilterSave())
  }

  filterOpChanged(e) {
    const row = e.currentTarget.closest(".filter-row")
    const field = row.querySelector(".filter-field").value
    this._redrawFilterRow(row, { field, op: e.currentTarget.value, value: this._filterValue(row) })
      .then(() => this._scheduleFilterSave())
  }

  // Value edits (the field and operator selects have their own handlers)
  filterChanged(e) {
    if (e.target.matches(".filter-field, .filter-op")) return
    this._scheduleFilterSave()
  }

  removeFilterRow(e) {
    e.currentTarget.closest(".filter-row").remove()
    this._scheduleFilterSave()
  }

  // Kept for the command palette and older callers: save straight away
  saveFilters() {
    clearTimeout(this.filterTimer)
    if (!this._filtersComplete()) return
    const childFilters = {}
    this.childFilterRowsTargets.forEach(container => {
      childFilters[container.dataset.relation] = this._collectFilters(container)
    })
    this._saveFiltersToServer(this._collectFilters(this.rootFilterRowsTarget), childFilters)
  }

  _scheduleFilterSave() {
    clearTimeout(this.filterTimer)
    this.filterTimer = setTimeout(() => this.saveFilters(), 600)
  }

  _filterContainer(relation) {
    if (!relation) return this.rootFilterRowsTarget
    return this.childFilterRowsTargets.find(el => el.dataset.relation === relation)
  }

  _fetchFilterRow(url, params) {
    const query = new URLSearchParams()
    Object.entries(params).forEach(([k, v]) => {
      if (Array.isArray(v)) v.forEach(item => query.append(`${k}[]`, item))
      else if (v !== undefined && v !== null) query.append(k, v)
    })
    const separator = url.includes("?") ? "&" : "?"
    return fetch(`${url}${separator}${query}`, { headers: { "Accept": "text/html" } }).then(r => r.text())
  }

  _redrawFilterRow(row, params) {
    const container = row.parentElement
    return this._fetchFilterRow(container.dataset.rowUrl, params).then(html => {
      row.outerHTML = html
    })
  }

  // The row's value as the server expects it: ISO date, chosen option(s), list or text
  _filterValue(row) {
    const kind = row.dataset.kind
    const op = row.querySelector(".filter-op")?.value
    if (kind === "date") return row.querySelector("[data-rb-filter-iso]")?.value || ""
    const input = row.querySelector(".filter-val")
    if (!input) return ""
    if (input.multiple) return Array.from(input.selectedOptions).map(o => o.value)
    if (op === "in") return input.value.split(",").map(v => v.trim()).filter(Boolean)
    return input.value.trim()
  }

  // Marks rows that can't be saved yet; true when every row with a field is complete (E9, E10)
  _filtersComplete() {
    const NO_VALUE_OPS = new Set(["null", "not_null"])
    const example = this.filtersPanelTarget.dataset.dateExample
    let complete = true
    this.element.querySelectorAll(".filter-row").forEach(row => {
      const error = row.querySelector(".filter-error")
      if (!error) return
      const op = row.querySelector(".filter-op")?.value
      const value = this._filterValue(row)
      let message = ""
      if (!NO_VALUE_OPS.has(op)) {
        const typed = row.querySelector("[data-locale-date-target='display']")?.value?.trim()
        if (row.dataset.kind === "date" && typed && !value) message = `Enter a date like ${example}`
        else if (Array.isArray(value) ? value.length === 0 : value === "") message = "needs a value"
      }
      error.textContent = message
      error.classList.toggle("d-none", message === "")
      if (message) complete = false
    })
    return complete
  }

  _collectFilters(container) {
    const NO_VALUE_OPS = new Set(["null", "not_null"])
    const filters = {}
    container.querySelectorAll(".filter-row").forEach(row => {
      const field = row.querySelector(".filter-field")?.value
      const op    = row.querySelector(".filter-op")?.value
      if (!field || !op) return
      filters[`${field}_${op}`] = NO_VALUE_OPS.has(op) ? "1" : this._filterValue(row)
    })
    return filters
  }

  _saveFiltersToServer(rootFilters, childFilters) {
    // We update root_filters directly and patch child_filters per join via joins array
    // Build the joins patch by reading the current join elements
    const joinEls = this.element.querySelectorAll("[data-report-builder-relation]")
    const joinsWithFilters = Array.from(joinEls).map(el => {
      const rel = el.dataset.reportBuilderRelation
      const join = {
        relation:      rel,
        model:         el.dataset.reportBuilderModel,
        fk:            el.dataset.reportBuilderFk,
        child_filters: childFilters[rel] || {}
      }
      try {
        const pivot = JSON.parse(el.dataset.reportBuilderPivot || "{}")
        if (pivot && Object.keys(pivot).length > 0) join.pivot = pivot
        // Keep "Only rows that have …" — this rebuild replaces the whole joins array
        if (el.dataset.reportBuilderOnlyWithRows === "true") join.only_with_rows = true
      } catch (_) {}
      return join
    })

    const patch = { root_filters: rootFilters }
    if (joinsWithFilters.length > 0) patch.joins = joinsWithFilters

    this._save(this.templateUrlValue, { template: patch }, "Filters")
  }

  _esc(str) {
    return String(str).replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;")
  }

  // ── Pivot preview ─────────────────────────────────────────────────────

  // Before Apply: "This will create N columns: A, B, …", warning above the limit (H16, E17)
  pivotPreview(e) {
    const form = e.currentTarget
    const out = form.querySelector("[data-pivot-preview]")
    const data = new FormData(form)
    const groupBys = data.getAll("group_bys[]").filter(Boolean)
    const valueCol = data.get("value_col")
    if (!out) return
    if (groupBys.length === 0 || !valueCol) { out.textContent = ""; return }

    const query = new URLSearchParams({ relation: data.get("relation"), value_col: valueCol })
    groupBys.forEach(g => query.append("group_bys[]", g))
    fetch(`${form.dataset.previewUrl}?${query}`, { headers: { "Accept": "application/json" } })
      .then(r => r.json())
      .then(result => {
        if (result.error) {
          out.className = "col-12 small text-danger"
          out.textContent = result.error
          return
        }
        const more = result.count > result.headers.length ? ", …" : ""
        const warn = result.count > result.warn_over ? " — consider fewer categories" : ""
        out.className = `col-12 small ${warn ? "text-danger" : "text-muted"}`
        out.textContent = `This will create ${result.count} column${result.count === 1 ? "" : "s"}: ${result.headers.join(", ")}${more}${warn}`
      })
  }

  // ── Related data settings ─────────────────────────────────────────────

  // "Only <rows> that have <related data>" switch on a join card (H13, H14):
  // saves the one join's setting, then refreshes the preview so the row
  // count reflects it
  toggleOnlyWithRows(e) {
    const relation = e.target.dataset.relation
    this._save(this.joinSettingsUrlValue, { relation, only_with_rows: e.target.checked }, "Related data setting", [e.target])
  }

  // ── Scheduling ────────────────────────────────────────────────────────

  // On: shows the form (nothing is saved until Save schedule). Off: a saved
  // schedule is turned off at once, without checking what's typed (E5)
  toggleSchedule(e) {
    const enabled = e.target.checked
    this.element.querySelector("#scheduleSettings").classList.toggle("d-none", !enabled)
    if (enabled || e.target.dataset.saved !== "1") return

    this._scheduleField("enabled").value = "false"
    this.element.querySelector("#rb_schedule_form").requestSubmit()
  }

  // Save schedule: ask the server about the recipients first — a bad address
  // is shown under the field (X2, X3); people outside the company get the
  // Immediate Actions popup (H5, E3); otherwise save straight away (H4).
  // The save re-checks, so skipping this can't save outsiders (X4).
  async saveSchedule() {
    const form = this.element.querySelector("#rb_schedule_form")
    const box = this.scheduleRecipientsTarget
    this._scheduleField("enabled").value = "true"
    this._scheduleField("frequency").value = this.scheduleFrequencyTarget.value
    this._scheduleField("timezone").value = this.scheduleTimezoneTarget.value
    this._scheduleField("recipients").value = box.value
    this._scheduleField("outsiders_ok").value = "0"

    let check
    try {
      const r = await fetch(this.element.querySelector(".rb-delivery").dataset.checkUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": this.csrfValue },
        body: JSON.stringify({ recipients: box.value, frequency: this.scheduleFrequencyTarget.value,
                               timezone: this.scheduleTimezoneTarget.value }),
      })
      if (!r.ok) throw new Error(`the server answered ${r.status}`)
      check = await r.json()
    } catch (err) {
      this._toast(`Schedule wasn't saved — ${err.message}`, "danger")
      return
    }

    const error = this.element.querySelector("#rb_schedule_recipients_error")
    box.classList.toggle("is-invalid", !!check.error)
    error.textContent = check.error || ""
    if (check.error) return

    if (check.outsiders && check.outsiders.length > 0) {
      const trigger = this.element.querySelector("#rb_schedule_confirm")
      this._scheduleField("outsiders_ok").value = "1"
      trigger.dataset.msg = check.summary_html
      trigger.click()
      return
    }
    form.requestSubmit()
  }

  _scheduleField(name) {
    return this.element.querySelector(`#rb_schedule_form [name="${name}"]`)
  }

  // ── Helpers ───────────────────────────────────────────────────────────


  _currentJoins() {
    const joins = []
    this.element.querySelectorAll("[data-report-builder-relation]").forEach(el => {
      const j = { relation: el.dataset.reportBuilderRelation,
                  model:    el.dataset.reportBuilderModel,
                  fk:       el.dataset.reportBuilderFk }
      try {
        const pv = el.dataset.reportBuilderPivot
        if (pv) {
          const parsed = JSON.parse(pv)
          if (parsed && Object.keys(parsed).length > 0) j.pivot = parsed
        }
      } catch (_) {}
      joins.push(j)
    })
    return joins
  }

  // Saves one setting and says truthfully whether it worked: green only once
  // the server confirms; otherwise red with the reason, and the controls go
  // back to their last saved values. Resolves to true when saved (H22, E25, X3).
  _save(url, body, setting, controls = []) {
    return this._patch(url, body)
      .then(data => {
        controls.forEach(el => this._remember(el))
        // A builder stream answer carries its own message
        if (!data.stream) this._toast(`${setting} saved`)
        return true
      })
      .catch(err => {
        controls.forEach(el => this._restore(el))
        this._toast(`${setting} wasn't saved — ${err.message}`, "danger")
        return false
      })
  }

  // PATCH as JSON. Rejects on any non-2xx response (with the server's own
  // message when it sends one) and when the server can't be reached
  _patch(url, body) {
    return fetch(url, {
      method:  "PATCH",
      headers: {
        "Content-Type":     "application/json",
        "X-CSRF-Token":     this.csrfValue,
        "Accept":           "text/vnd.turbo-stream.html, application/json",
        "X-Report-Builder": "1",
      },
      body: JSON.stringify(body),
    })
    .catch(() => { throw new Error("the server couldn't be reached") })
    .then(async r => {
      // Success from a builder change: panel, preview and health as Turbo Streams (H2)
      if (r.ok && (r.headers.get("Content-Type") || "").includes("turbo-stream")) {
        window.Turbo.renderStreamMessage(await r.text())
        return { stream: true }
      }
      const data = await r.json().catch(() => ({}))
      if (!r.ok) {
        const reason = (data.errors && data.errors.join(", ")) || data.error ||
                       (r.status === 401 ? "your session has expired, sign in again" : `the server answered ${r.status}`)
        throw new Error(reason)
      }
      return data
    })
  }

  _remember(el) {
    if (!el) return
    el.dataset.savedValue = el.type === "checkbox" ? String(el.checked) : el.value
  }

  _restore(el) {
    if (!el || el.dataset.savedValue === undefined) return
    if (el.type === "checkbox") {
      el.checked = el.dataset.savedValue === "true"
    } else {
      el.value = el.dataset.savedValue
    }
  }

  _toast(msg, level = "success") {
    const el = document.createElement("div")
    el.className = `toast align-items-center text-bg-${level} border-0 position-fixed report-builder-toast`
    el.style.cssText = "bottom:1rem;right:1rem;z-index:9999;min-width:160px"
    el.setAttribute("role", "alert")
    el.innerHTML = `
      <div class="d-flex">
        <div class="toast-body fw-semibold">${this._esc(msg)}</div>
      </div>`
    document.body.appendChild(el)
    const t = new bootstrap.Toast(el, { delay: 1800 })
    t.show()
    el.addEventListener("hidden.bs.toast", () => el.remove())
  }
}
