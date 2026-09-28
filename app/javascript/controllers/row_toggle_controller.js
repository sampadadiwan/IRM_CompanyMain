import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["control"]

  connect() {
    // hide all child rows on initialize
    this.element.querySelectorAll("tbody tr.child, tbody tr.subchild").forEach(ch => {
      ch.style.display = "none"
    })
    // reset only the symbol spans inside control targets
    this.controlTargets.forEach(ctrl => {
      const span = ctrl.querySelector("span.expand")
      if (span) {
        // Reset the symbol to the collapsed state
        // use +/- and not >
        span.textContent = "+"
        span.classList.remove("expanded")
      }
      // Set initial aria-expanded
      ctrl.setAttribute("aria-expanded", "false")
    })

    this.detectStripingColors()
    this.applyStriping()
    this.setupMutationObserver()
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
    }
    if (this.stripingFrame) {
      cancelAnimationFrame(this.stripingFrame)
    }
  }

  detectStripingColors() {
    const dummy = document.createElement('div')
    // Use the same classes as the actual table to ensure we pick up the right styles
    dummy.innerHTML = `
      <table class="${this.element.className}">
        <tbody>
          <tr><td></td></tr>
          <tr><td></td></tr>
        </tbody>
      </table>
    `
    dummy.style.position = 'absolute'
    dummy.style.left = '-9999px'
    dummy.style.visibility = 'hidden'
    document.body.appendChild(dummy)

    const rows = dummy.querySelectorAll('tr')
    // nth-child(odd) is rows[0], nth-child(even) is rows[1]
    this.oddColor = window.getComputedStyle(rows[0]).backgroundColor
    this.evenColor = window.getComputedStyle(rows[1]).backgroundColor

    document.body.removeChild(dummy)
    this.createStripingStyles(this.oddColor, this.evenColor)
  }

  createStripingStyles(odd, even) {
    const styleId = 'row-toggle-striping-styles'
    let style = document.getElementById(styleId)
    if (!style) {
      style = document.createElement('style')
      style.id = styleId
      document.head.appendChild(style)
    }
    // Use high specificity to override kedaara.css !important nth-child rules
    style.textContent = `
      table[data-controller="row-toggle"] tbody tr.collapsible-table-odd { background-color: ${odd} !important; }
      table[data-controller="row-toggle"] tbody tr.collapsible-table-even { background-color: ${even} !important; }
    `
  }

  setupMutationObserver() {
    const tbody = this.element.querySelector("tbody")
    if (!tbody) return

    this.observer = new MutationObserver(() => {
      this.applyStriping()
    })

    this.observer.observe(tbody, { childList: true, subtree: true })
  }

  toggle(event) {
    const control = event.currentTarget
    const symbol = control.querySelector("span.expand")
    const opening = symbol && !symbol.classList.contains("expanded")
    const parentRow = control.closest("tr")
    let next = parentRow.nextElementSibling
    // Tracks whether the most recently seen subgroup header (.parent-sub) is itself
    // expanded, so nested .subchild rows only reappear when both the top-level group
    // AND their own subgroup are expanded.
    let currentSubgroupExpanded = true

    while (next && !next.classList.contains("parent")) {
      if (next.classList.contains("child")) {
        next.style.display = opening ? "table-row" : "none"
        if (opening) {
          next.classList.add("row-fade-in")
        } else {
          next.classList.remove("row-fade-in")
        }

        if (next.classList.contains("parent-sub")) {
          const subSymbol = next.querySelector("span.expand")
          currentSubgroupExpanded = subSymbol ? subSymbol.classList.contains("expanded") : true
        }
      } else if (next.classList.contains("subchild")) {
        const showRow = opening && currentSubgroupExpanded
        next.style.display = showRow ? "table-row" : "none"
        next.classList.toggle("row-fade-in", showRow)
      }
      next = next.nextElementSibling
    }

    if (symbol) {
      symbol.textContent = opening ? "−" : "+"
      symbol.classList.toggle("expanded", opening)
    }

    control.setAttribute("aria-expanded", opening ? "true" : "false")

    this.applyStriping()
  }

  // Toggles the nested investor rows (.subchild) belonging to a subgroup header row (.child.parent-sub).
  // Stops at the next top-level row (.child or .parent) so it never touches sibling subgroups.
  toggleSub(event) {
    const control = event.currentTarget
    const symbol = control.querySelector("span.expand")
    const opening = symbol && !symbol.classList.contains("expanded")
    const parentRow = control.closest("tr")
    let next = parentRow.nextElementSibling

    while (next && !next.classList.contains("child") && !next.classList.contains("parent")) {
      if (next.classList.contains("subchild")) {
        next.style.display = opening ? "table-row" : "none"
        if (opening) {
          next.classList.add("row-fade-in")
        } else {
          next.classList.remove("row-fade-in")
        }
      }
      next = next.nextElementSibling
    }

    if (symbol) {
      symbol.textContent = opening ? "−" : "+"
      symbol.classList.toggle("expanded", opening)
    }

    control.setAttribute("aria-expanded", opening ? "true" : "false")

    this.applyStriping()
  }

  applyStriping() {
    if (this.stripingFrame) {
      cancelAnimationFrame(this.stripingFrame)
    }

    this.stripingFrame = requestAnimationFrame(() => {
      const rows = this.element.querySelectorAll("tbody tr")
      let visibleIndex = 0

      rows.forEach((row) => {
        const isVisible = row.style.display !== "none" && !row.classList.contains("d-none")

        row.classList.remove("collapsible-table-odd", "collapsible-table-even")

        if (isVisible) {
          const className = visibleIndex % 2 === 0 ? "collapsible-table-odd" : "collapsible-table-even"
          row.classList.add(className)
          visibleIndex++
        }
      })
    })
  }
}
