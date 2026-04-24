import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "nameDisplay", "nameInput",
    "previewFrame",
    "sortKey", "sortDir",
    "filtersPanel", "rootFilterRows", "childFilterRows",
    "paletteSearch", "paletteRow", "exportBtn",
    "formulaInput", "formulaPreview", "formulaSubmit",
    "viewTarget",
    "scheduleFrequency", "scheduleRecipients",
    "groupRowsBy"
  ]

  static values = {
    aggregateUrl: String,
    sortUrl:      String,
    nameUrl:      String,
    templateUrl:  String,
    previewUrl:   String,
    validateFormulaUrl: String,
    viewSettingsUrl: String,
    scheduleUrl: String,
    csrf:         String,
  }

  // ── Export ────────────────────────────────────────────────────────────

  startExport(e) {
    const btn = e.currentTarget
    const originalContent = btn.innerHTML
    
    btn.disabled = true
    btn.innerHTML = `<span class="spinner-border spinner-border-sm me-2"></span>Generating...`
    
    // The link will still trigger the GET request to the controller
    // We just want to show a loading state until the page reloads or the notice appears
    setTimeout(() => {
      btn.disabled = false
      btn.innerHTML = originalContent
    }, 3000)
  }

  // ── Palette Search ────────────────────────────────────────────────────

  filterPalette() {
    const query = this.paletteSearchTarget.value.toLowerCase().trim()
    
    // If searching, open all groups to show results
    if (query.length > 0) {
      this.element.querySelectorAll(".palette-group").forEach(el => el.open = true)
    }

    this.paletteRowTargets.forEach(row => {
      const text = row.dataset.searchText || row.querySelector("span").textContent.toLowerCase()
      row.classList.toggle("d-none", !text.includes(query))
    })
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
    this._patch(this.nameUrlValue, { name })
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
    this._patch(this.aggregateUrlValue, { key, aggregate: agg })
      .then(() => this._toast("Aggregate saved"))
  }

  // ── Sort ──────────────────────────────────────────────────────────────

  sortChanged() {
    const sortKey = this.sortKeyTarget.value
    const sortDir = this.sortDirTarget.value
    this._patch(this.sortUrlValue, { sort_key: sortKey, sort_dir: sortDir })
      .then(() => this._toast("Sort saved"))
  }

  groupingChanged() {
    const groupRowsBy = this.groupRowsByTarget.value
    this._patch(this.templateUrlValue, { template: { group_rows_by: groupRowsBy } })
      .then(() => this._toast("Grouping saved"))
  }

  switchMode(e) {
    const mode = e.target.value
    const setupRow = this.element.querySelector("#report_builder_setup_row")
    const previewRow = this.element.querySelector("#report_builder_preview_row")

    if (mode === "view") {
      setupRow.classList.add("d-none")
      if (previewRow) previewRow.classList.remove("d-none")
      this.loadPreview()
    } else {
      setupRow.classList.remove("d-none")
      if (previewRow) previewRow.classList.add("d-none")
    }
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

  validateFormula() {
    const expression = this.formulaInputTarget.value.trim()
    const preview    = this.formulaPreviewTarget
    const submit     = this.formulaSubmitTarget

    if (!expression) {
      preview.innerHTML = '<span class="text-muted">Enter an expression to see preview...</span>'
      submit.disabled = true
      return
    }

    // Debounce validation
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
          preview.innerHTML = '<span class="text-success"><i class="ti ti-check me-1"></i> Valid formula</span>'
          submit.disabled = false
        } else {
          preview.innerHTML = `<span class="text-danger"><i class="ti ti-alert-circle me-1"></i> ${data.error}</span>`
          submit.disabled = true
        }
      })
    }, 300)
  }

  // ── Filters ───────────────────────────────────────────────────────────

  addFilterRow(e) {
    const btn      = e.currentTarget
    const scope    = btn.dataset.scope       // "root" or "child"
    const relation = btn.dataset.relation || null

    // Find the correct container
    let container
    if (scope === "root") {
      container = this.rootFilterRowsTarget
    } else {
      container = this.childFilterRowsTargets.find(el => el.dataset.relation === relation)
    }
    if (!container) return

    const columns = JSON.parse(container.dataset.columns || "[]")

    const fieldOpts = columns.map(c =>
      `<option value="${this._esc(c.key)}">${this._esc(c.label)}</option>`
    ).join("")

    const NO_VALUE_OPS = new Set(["null", "not_null"])

    const opOpts = [
      ["=", "eq"], ["contains", "cont"], ["any of", "in"],
      ["≠", "not_eq"], ["≥", "gteq"], ["≤", "lteq"],
      ["is nil", "null"], ["is not nil", "not_null"]
    ].map(([lbl, op]) => `<option value="${op}">${lbl}</option>`).join("")

    const row = document.createElement("div")
    row.className = "d-flex gap-1 align-items-center mb-2 filter-row p-1"
    row.dataset.scope = scope
    if (relation) row.dataset.relation = relation
    row.innerHTML = `
      <select class="form-select form-select-sm filter-field border-0 bg-light" style="width:36%">
        <option value="">— field —</option>${fieldOpts}
      </select>
      <select class="form-select form-select-sm filter-op border-0 bg-light" style="width:26%">${opOpts}</select>
      <input type="text" class="form-control form-control-sm filter-val border-0 bg-light"
             placeholder="value" style="flex:1; min-width:60px">
      <button type="button" class="btn btn-link text-danger p-0 opacity-50 flex-shrink-0"
              data-action="click->report-builder#removeFilterRow">
        <i class="ti ti-trash" style="font-size:.9rem"></i>
      </button>`

    // Hide value input when a no-value operator is selected
    const opSel  = row.querySelector(".filter-op")
    const valIn  = row.querySelector(".filter-val")
    const toggleVal = () => {
      const hide = NO_VALUE_OPS.has(opSel.value)
      valIn.style.display = hide ? "none" : ""
      if (hide) valIn.value = ""
    }
    opSel.addEventListener("change", toggleVal)

    container.appendChild(row)
  }

  removeFilterRow(e) {
    e.currentTarget.closest(".filter-row").remove()
  }

  filterOpChanged(e) {
    const NO_VALUE_OPS = new Set(["null", "not_null"])
    const row  = e.currentTarget.closest(".filter-row")
    const valIn = row.querySelector(".filter-val")
    const hide  = NO_VALUE_OPS.has(e.currentTarget.value)
    valIn.style.display = hide ? "none" : ""
    if (hide) valIn.value = ""
  }

  saveFilters() {
    const rootFilters  = this._collectFilters(this.rootFilterRowsTarget)
    const childFilters = {}

    this.childFilterRowsTargets.forEach(container => {
      const relation = container.dataset.relation
      if (relation) childFilters[relation] = this._collectFilters(container)
    })

    // Build joins array update: patch child_filters into each join entry
    // We deep-merge via the template endpoint
    const tmplPatch = { root_filters: rootFilters }

    // Collect join updates — we need the current joins list to merge into
    const joinEls = this.element.querySelectorAll("[data-report-builder-relation]")
    const joins = Array.from(joinEls).map(el => ({
      relation:     el.dataset.reportBuilderRelation,
      model:        el.dataset.reportBuilderModel,
      fk:           el.dataset.reportBuilderFk,
      child_filters: childFilters[el.dataset.reportBuilderRelation] || {}
    }))
    if (joins.length > 0) tmplPatch.joins_filters = joins

    this._saveFiltersToServer(rootFilters, childFilters)
  }

  _collectFilters(container) {
    const NO_VALUE_OPS = new Set(["null", "not_null"])
    const filters = {}
    container.querySelectorAll(".filter-row").forEach(row => {
      const field = row.querySelector(".filter-field")?.value?.trim()
      const op    = row.querySelector(".filter-op")?.value?.trim()
      const raw   = row.querySelector(".filter-val")?.value?.trim()
      if (!field || !op) return
      if (!NO_VALUE_OPS.has(op) && !raw) return   // value required for all other ops

      const pred = `${field}_${op}`
      if (NO_VALUE_OPS.has(op)) {
        filters[pred] = "1"   // Ransack _null / _not_null expect "1"
      } else if (op === "in") {
        filters[pred] = raw.split(",").map(v => v.trim()).filter(Boolean)
      } else {
        filters[pred] = raw
      }
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
      } catch (_) {}
      return join
    })

    const patch = { root_filters: rootFilters }
    if (joinsWithFilters.length > 0) patch.joins = joinsWithFilters

    this._patch(this.templateUrlValue, { template: patch })
      .then(() => this._toast("Filters saved"))
  }

  _esc(str) {
    return String(str).replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;")
  }

  // ── View & Sharing ────────────────────────────────────────────────────

  toggleView(e) {
    const isView = e.target.checked
    const section = this.element.querySelector("#viewTargetSection")
    section.classList.toggle("d-none", !isView)
    this._patch(this.viewSettingsUrlValue, { is_view: isView })
      .then(() => this._toast("View setting saved"))
  }

  updateViewTarget(e) {
    const viewTarget = e.target.value
    this._patch(this.viewSettingsUrlValue, { view_target: viewTarget })
      .then(() => this._toast("View target saved"))
  }

  toggleShared(e) {
    const shared = e.target.checked
    this._patch(this.viewSettingsUrlValue, { shared: shared })
      .then(() => this._toast("Sharing setting saved"))
  }

  // ── Scheduling ────────────────────────────────────────────────────────

  toggleSchedule(e) {
    const active = e.target.checked
    const section = this.element.querySelector("#scheduleSettings")
    section.classList.toggle("d-none", !active)
    this.updateSchedule()
  }

  updateSchedule() {
    const active = this.element.querySelector("#scheduleActiveToggle").checked
    const frequency = this.scheduleFrequencyTarget.value
    const recipients = this.scheduleRecipientsTarget.value

    this._patch(this.scheduleUrlValue, { active, frequency, recipients })
      .then(() => this._toast("Schedule saved"))
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

  _patch(url, body) {
    return fetch(url, {
      method:  "PATCH",
      headers: {
        "Content-Type":  "application/json",
        "X-CSRF-Token":  this.csrfValue,
        "Accept":        "application/json",
      },
      body: JSON.stringify(body),
    })
    .then(r => r.json())
    .catch(err => console.error("report-builder fetch error", err))
  }

  _toast(msg) {
    const el = document.createElement("div")
    el.className = "toast align-items-center text-bg-success border-0 position-fixed"
    el.style.cssText = "bottom:1rem;right:1rem;z-index:9999;min-width:160px"
    el.setAttribute("role", "alert")
    el.innerHTML = `
      <div class="d-flex">
        <div class="toast-body fw-semibold">${msg}</div>
      </div>`
    document.body.appendChild(el)
    const t = new bootstrap.Toast(el, { delay: 1800 })
    t.show()
    el.addEventListener("hidden.bs.toast", () => el.remove())
  }
}
