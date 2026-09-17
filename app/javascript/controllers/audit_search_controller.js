import { Controller } from "@hotwired/stimulus"

// Client-side text filter for the audit trail tables (app/packs/core/base/views/audits/index.html.erb
// and the AuditTrail ViewComponent embedded on record show pages). Each event
// is two <tr>s (a visible summary row + a collapsed field-diff row right after
// it); we filter on both rows' combined text and toggle them together.
export default class extends Controller {
  static targets = ["row", "input", "actionCheckbox"]

  filter() {
    const term = this.inputTarget.value.trim().toLowerCase()
    const activeActions = this.hasActionCheckboxTarget
      ? this.actionCheckboxTargets.filter((cb) => cb.checked).map((cb) => cb.value)
      : null

    this.rowTargets.forEach((row) => {
      const detail = row.nextElementSibling
      const detailIsDetail = detail && detail.classList.contains("audit-trail-detail-row")
      const haystack = row.textContent + (detailIsDetail ? detail.textContent : "")
      const textMatches = !term || haystack.toLowerCase().includes(term)
      const actionMatches = !activeActions || activeActions.includes(row.dataset.auditAction)
      const matches = textMatches && actionMatches

      row.style.display = matches ? "" : "none"
      if (!detailIsDetail) return

      detail.style.display = matches ? "" : "none"

      // A text search hit is often buried in the field diff, not the summary
      // row — auto-expand matches so the user doesn't have to click through
      // to find it. Collapse back once the search is cleared.
      if (matches && term) {
        bootstrap.Collapse.getOrCreateInstance(detail, { toggle: false }).show()
      } else if (!term) {
        bootstrap.Collapse.getOrCreateInstance(detail, { toggle: false }).hide()
      }
    })
  }
}
