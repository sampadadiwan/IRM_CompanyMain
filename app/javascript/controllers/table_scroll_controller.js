import { Controller } from "@hotwired/stimulus"

// Shows overlay buttons to scroll a wide table horizontally when it overflows
// its container, so cut-off columns are reachable without hunting for the
// native scrollbar. Buttons are hidden when there's nothing to scroll to on
// that side.
export default class extends Controller {
  static targets = ["scrollArea", "left", "right"]

  connect() {
    // Bind once so the same reference can be passed to removeEventListener/disconnect on teardown.
    this.update = this.update.bind(this)

    this.scrollAreaTarget.addEventListener("scroll", this.update, { passive: true })
    window.addEventListener("resize", this.update)

    if ("ResizeObserver" in window) {
      this.resizeObserver = new ResizeObserver(this.update)
      this.resizeObserver.observe(this.scrollAreaTarget)
      // The wrapper's own box rarely changes size when its content merely
      // overflows it (that's what makes it scrollable in the first place),
      // so also observe the table itself to catch column/content-width
      // changes (e.g. ag-Grid autosizing, KPI columns toggling) that don't
      // touch the wrapper's box and wouldn't otherwise fire this observer.
      const table = this.scrollAreaTarget.querySelector("table")
      if (table) this.resizeObserver.observe(table)
    }

    this.update()
  }

  disconnect() {
    this.scrollAreaTarget.removeEventListener("scroll", this.update)
    window.removeEventListener("resize", this.update)
    this.resizeObserver?.disconnect()
  }

  update() {
    const el = this.scrollAreaTarget
    // +1 tolerance avoids treating sub-pixel rounding as scrollable content.
    const canScroll = el.scrollWidth > el.clientWidth + 1

    this.leftTarget.hidden = !canScroll || el.scrollLeft <= 0
    // -1 tolerance for the same sub-pixel rounding when checking the scrolled-to-end edge.
    this.rightTarget.hidden = !canScroll || el.scrollLeft + el.clientWidth >= el.scrollWidth - 1

    this.positionButtons()
  }

  // Size the buttons to a circle a third of the header's height, centered on the
  // header row(s). Rect-based math (rather than offsetHeight/CSS top) keeps
  // this aligned with the header's actual rendered edges regardless of
  // borders or the table's rounded-corner clipping.
  positionButtons() {
    const thead = this.scrollAreaTarget.querySelector("thead")
    if (!thead) return

    const wrapperRect = this.element.getBoundingClientRect()
    const theadRect = thead.getBoundingClientRect()

    const diameter = theadRect.height / 3
    const top = (theadRect.top - wrapperRect.top) + (theadRect.height - diameter) / 2

    for (const target of [this.leftTarget, this.rightTarget]) {
      target.style.width = `${diameter}px`
      target.style.height = `${diameter}px`
      target.style.top = `${top}px`
      target.style.fontSize = `${diameter * 0.45}px`
    }
  }

  scrollLeft() {
    this.scrollAreaTarget.scrollBy({ left: -this.scrollAmount(), behavior: "smooth" })
  }

  scrollRight() {
    this.scrollAreaTarget.scrollBy({ left: this.scrollAmount(), behavior: "smooth" })
  }

  scrollAmount() {
    // 75% of the viewport per click, so the trailing 25% stays visible as
    // context for where the view landed.
    return Math.round(this.scrollAreaTarget.clientWidth * 0.75)
  }
}
