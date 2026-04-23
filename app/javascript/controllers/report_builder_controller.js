import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "nameDisplay", "nameInput",
    "previewFrame",
    "sortKey", "sortDir",
    "filtersPanel", "rootFilterRows", "childFilterRows",
    "paletteSearch", "paletteRow", "exportBtn"
  ]

  static values = {
    aggregateUrl: String,
    sortUrl:      String,
    nameUrl:      String,
    templateUrl:  String,
    previewUrl:   String,
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

  // ── Join select – populate hidden fields before form submit ──────────

  joinSelectChanged(e) {
    const select = e.target
    const form   = select.closest("form")
    if (!select.value) {
      form.querySelector("[name=relation]").value = ""
      return
    }
    try {
      const assoc = JSON.parse(select.value)
      form.querySelector("[name=relation]").value = assoc.name        || ""
      form.querySelector("[name=model]").value    = assoc.model       || ""
      form.querySelector("[name=fk]").value       = assoc.foreign_key || ""
    } catch (_) { /* ignore parse errors */ }
  }

  // ── Preview ───────────────────────────────────────────────────────────

  loadPreview() {
    const frame = this.previewFrameTarget
    const url = this.previewUrlValue
    
    if (!url || url === "undefined") {
      console.error("ReportBuilder: previewUrlValue is missing", { url })
      this._toast("Error: Preview URL is missing", "danger")
      return
    }

    frame.innerHTML = `
      <div class="text-center py-5">
        <div class="spinner-border text-primary" role="status"></div>
        <div class="text-muted small mt-2">Loading preview...</div>
      </div>
    `
    frame.setAttribute("src", url)
  }

  // ── Filter management ─────────────────────────────────────────────────

  addFilterRow(e) {
    const btn      = e.currentTarget
    const scope    = btn.dataset.scope
    const relation = btn.dataset.relation

    // Find the matching rows container (sibling above the button)
    let container
    if (scope === "root") {
      container = this.rootFilterRowsTarget
    } else {
      container = this.childFilterRowsTargets.find(el => el.dataset.relation === relation)
    }
    if (!container) return

    let columns = []
    try { columns = JSON.parse(container.dataset.columns || "[]") } catch (_) {}

    const fieldOpts = ['<option value="">— field —</option>',
      ...columns.map(c => `<option value="${c.key}">${c.label}</option>`)
    ].join("")

    const OPS = [["=","eq"],["contains","cont"],["any of","in"],["≠","not_eq"],["≥","gteq"],["≤","lteq"]]
    const opOpts = OPS.map(([l, v]) => `<option value="${v}">${l}</option>`).join("")

    const row = document.createElement("div")
    row.className = "d-flex gap-1 align-items-center mb-2 filter-row p-1"
    row.dataset.scope = scope
    if (relation) row.dataset.relation = relation

    row.innerHTML = `
      <select class="form-select form-select-sm filter-field border-0 bg-light" style="width:36%">${fieldOpts}</select>
      <select class="form-select form-select-sm filter-op border-0 bg-light" style="width:26%">${opOpts}</select>
      <input type="text" class="form-control form-control-sm filter-val border-0 bg-light"
             placeholder="value" style="flex:1; min-width:60px">
      <button type="button" class="btn btn-link text-danger p-0 opacity-50 hover-opacity-100 flex-shrink-0"
              data-action="click->report-builder#removeFilterRow">
        <i class="ti ti-trash" style="font-size:.9rem"></i>
      </button>
    `

    // Update placeholder when operator changes
    row.querySelector(".filter-op").addEventListener("change", ev => {
      row.querySelector(".filter-val").placeholder =
        ev.target.value === "in" ? "val1, val2, …" : "value"
    })

    container.appendChild(row)
    row.querySelector(".filter-field").focus()
  }

  removeFilterRow(e) {
    e.currentTarget.closest(".filter-row").remove()
  }

  saveFilters() {
    const rootFilters  = {}
    const childFilters = {}  // { relation: { pred: val } }

    this.element.querySelectorAll(".filter-row").forEach(row => {
      const field = row.querySelector(".filter-field")?.value
      const op    = row.querySelector(".filter-op")?.value
      let   val   = row.querySelector(".filter-val")?.value?.trim()

      if (!field || !op) return
      const pred = `${field}_${op}`

      // For 'in' operator, split comma-separated string into array
      if (op === "in" || op === "not_in") {
        val = val ? val.split(",").map(s => s.trim()).filter(s => s.length > 0) : []
      }

      if (row.dataset.scope === "root") {
        rootFilters[pred] = val
      } else {
        const rel = row.dataset.relation
        if (!childFilters[rel]) childFilters[rel] = {}
        childFilters[rel][pred] = val
      }
    })

    // Build template delta
    const joins = this._currentJoins()
    const updatedJoins = joins.map(j => {
      const rel = j.relation || j["relation"]
      return { ...j, child_filters: childFilters[rel] || {} }
    })

    const delta = { root_filters: rootFilters, joins: updatedJoins }
    this._patch(this.templateUrlValue, { template: delta })
      .then(() => this._toast("Filters saved"))
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
