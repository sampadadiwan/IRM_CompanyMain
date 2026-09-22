import { Controller } from "@hotwired/stimulus"

// A table of one allocation run's entry-name totals: search, a "hide zero" toggle, a "top-level
// only" toggle, and rows that open — recursively — into the totals each one is built from.
//
// Every dependency is another total on the same sheet, so the page carries the whole graph as
// JSON (the `graph` target) and builds child rows from it when a row is opened. Nothing is
// fetched. The children are built on demand rather than rendered up front because a real run
// chains 19 levels deep and one total feeds many parents: rendering every branch in advance
// would repeat the same subtree under every parent that uses it, which grows exponentially.
//
// A total is never opened beneath itself: the ancestors of each row travel with it, and a
// dependency already on that path is shown as a loop instead of expanded again.
//
// Not list_filter_controller: that one is shared with other screens and only matches text.
export default class extends Controller {
  static targets = ["row", "search", "count", "empty", "zeroToggle", "topToggle", "graph"]
  static values = { linkTemplate: String, placeholder: String }

  connect() {
    this.graph = this.hasGraphTarget ? JSON.parse(this.graphTarget.textContent) : {}
    this.nextKey = 0
    this.apply()
  }

  // ── opening and closing ──────────────────────────────────────────────────────

  toggle(event) {
    const row = event.currentTarget.closest("tr")
    if (!row) return
    row.dataset.open === "true" ? this.collapse(row) : this.expand(row)
  }

  expand(row) {
    const name = row.dataset.entryTotalsName
    const node = this.graph[name]
    if (!node || node.deps.length === 0) return

    const key = this.keyFor(row)
    const path = this.pathOf(row)
    const ancestors = `${row.dataset.ancestors || ""} ${key}`.trim()
    const depth = Number(row.dataset.depth || 0) + 1

    let anchor = row
    node.deps.forEach((depName) => {
      const child = this.buildRow(depName, {
        depth, ancestors, path: [...path, depName],
        sign: (node.signs || {})[depName] ?? 1,
        loop: path.includes(depName),
        earlier: (node.earlier || []).includes(depName)
      })
      anchor.after(child)
      anchor = child
    })

    row.dataset.open = "true"
    this.setChevron(row, true)
  }

  collapse(row) {
    const key = row.dataset.key
    if (key) this.element.querySelectorAll(`tr[data-ancestors~="${key}"]`).forEach((tr) => tr.remove())
    row.dataset.open = "false"
    this.setChevron(row, false)
  }

  collapseAll() {
    this.rowTargets.forEach((row) => { if (row.dataset.open === "true") this.collapse(row) })
  }

  // ── filtering ────────────────────────────────────────────────────────────────

  apply() {
    const term = this.hasSearchTarget ? this.searchTarget.value.trim().toLowerCase() : ""
    const hideZero = this.hasZeroToggleTarget && this.zeroToggleTarget.checked
    const topOnly = this.hasTopToggleTarget && this.topToggleTarget.checked
    // With a graph (the Dependencies tab) nothing is listed until the reader narrows it: a run
    // has hundreds of totals and a wall of them answers no question. Searching, or asking for
    // the top-level numbers, is what reveals rows. Hide-zero does not count — it is on by default.
    const filtering = !this.hasGraphTarget || term !== "" || topOnly
    let visible = 0

    this.rowTargets.forEach((row) => {
      const show = filtering && this.shows(row, term, hideZero, topOnly)
      // An opened branch belongs to its row; hiding the row without closing it would leave its
      // children stranded under whatever row now sits above them.
      if (!show && row.dataset.open === "true") this.collapse(row)
      row.hidden = !show
      if (show) visible += 1
    })

    if (this.hasCountTarget) this.countTarget.textContent = visible

    // Say which filter emptied the table. "No entry name matches that search" over an empty
    // search box sends the reader looking for a search they never made.
    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = visible !== 0
      if (visible === 0) {
        this.emptyTarget.textContent = !filtering
          ? "Search for an entry name, or tick “Top-level numbers only”, to see what the totals are built from."
          : term !== ""
          ? "No entry name matches that search."
          : "Nothing to show with these filters. Untick “hide rows totalling zero” or “top-level numbers only”."
      }
    }
  }

  // A row survives the search when its own name matches, or when one of the totals it is built
  // from does — a reviewer searching "management fees" wants the totals that include it too.
  shows(row, term, hideZero, topOnly) {
    const name = row.dataset.entryTotalsName || ""
    const node = this.graph[name]
    if (hideZero && row.dataset.entryTotalsZero === "true") return false
    if (topOnly && node && !node.top) return false
    if (term === "") return true

    const deps = node ? node.deps.join(" ") : (row.dataset.entryTotalsDeps || "")
    return `${name} ${deps}`.toLowerCase().includes(term)
  }

  clear() {
    if (this.hasSearchTarget) this.searchTarget.value = ""
    this.apply()
  }

  // ── building a child row ─────────────────────────────────────────────────────

  buildRow(name, { depth, ancestors, path, sign, loop, earlier }) {
    const node = this.graph[name] || { deps: [], total: "—", entries: 0 }
    const tr = document.createElement("tr")
    tr.className = "entry-totals-child"
    tr.dataset.entryTotalsName = name
    tr.dataset.depth = depth
    tr.dataset.ancestors = ancestors
    tr.dataset.path = JSON.stringify(path)

    const nameCell = document.createElement("td")
    nameCell.style.paddingLeft = `${0.5 + depth * 1.5}rem`

    const openable = !loop && node.deps.length > 0
    if (openable) {
      nameCell.appendChild(this.chevronButton())
    } else {
      const spacer = document.createElement("span")
      spacer.className = "d-inline-block me-1"
      spacer.style.width = "1rem"
      nameCell.appendChild(spacer)
    }

    if (sign < 0) {
      const minus = document.createElement("span")
      minus.className = "text-danger fw-bold me-1"
      minus.textContent = "−"
      minus.title = "Taken away, not added"
      nameCell.appendChild(minus)
    }

    const label = document.createElement("span")
    label.className = sign < 0 ? "text-danger" : ""
    label.textContent = name
    nameCell.appendChild(label)

    // The formula reads this name at another date — last quarter's closing figure, say — while
    // the total beside it is this run's. The link is real; the number is not the one it read.
    if (earlier) {
      const note = document.createElement("span")
      note.className = "text-body-secondary small ms-2"
      note.title = "The formula reads this at an earlier date. The figure shown is this run's own total, not the one it read."
      note.textContent = "· read from an earlier period"
      nameCell.appendChild(note)
    }

    if (loop) {
      const note = document.createElement("span")
      note.className = "text-body-secondary small ms-2"
      note.title = "This total is already open further up this branch"
      note.textContent = "↻ already shown above"
      nameCell.appendChild(note)
    }

    const totalCell = document.createElement("td")
    totalCell.className = "text-end figure"
    totalCell.textContent = node.total

    const entriesCell = document.createElement("td")
    entriesCell.className = "text-end text-body-secondary"
    entriesCell.textContent = node.entries

    const linkCell = document.createElement("td")
    if (this.hasLinkTemplateValue) {
      const a = document.createElement("a")
      a.className = "btn btn-sm btn-outline-info"
      a.href = this.linkTemplateValue.replace(this.placeholderValue, encodeURIComponent(name))
      a.dataset.turboFrame = "_top"
      a.title = "The folio entries behind this total"
      a.innerHTML = '<i class="ti ti-users"></i>'
      linkCell.appendChild(a)
    }

    tr.append(nameCell, totalCell, entriesCell, linkCell)
    return tr
  }

  chevronButton() {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "btn btn-sm btn-link p-0 me-1 text-decoration-none"
    button.dataset.action = "entry-totals#toggle"
    button.title = "What this total is built from"
    button.innerHTML = '<i class="ti ti-chevron-right"></i>'
    return button
  }

  setChevron(row, open) {
    const icon = row.querySelector("button i")
    if (icon) icon.className = open ? "ti ti-chevron-down" : "ti ti-chevron-right"
  }

  // ── bookkeeping ──────────────────────────────────────────────────────────────

  keyFor(row) {
    if (!row.dataset.key) row.dataset.key = `n${this.nextKey++}`
    return row.dataset.key
  }

  pathOf(row) {
    if (row.dataset.path) return JSON.parse(row.dataset.path)
    return [row.dataset.entryTotalsName]
  }
}
