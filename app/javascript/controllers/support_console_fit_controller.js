import { Controller } from "@hotwired/stimulus"

// Support Console: sizes the two panes (conversations + chat) to exactly fill the window below
// the page title, so no space is left under the cards and the page itself never scrolls.
const BOTTOM_GAP_PX = 12
const MIN_HEIGHT_PX = 480

export default class extends Controller {
  connect() {
    this.fit()
    window.addEventListener("resize", this.fit)
  }

  disconnect() {
    window.removeEventListener("resize", this.fit)
  }

  fit = () => {
    // Stacked layout below Bootstrap's lg breakpoint: the CSS sizes each pane instead.
    if (window.innerWidth < 992) {
      this.element.style.height = ""
      return
    }
    // Space from the panes' top edge to the bottom of the viewport, minus a small margin.
    const top = this.element.getBoundingClientRect().top + window.scrollY
    const height = Math.max(MIN_HEIGHT_PX, window.innerHeight - top - BOTTOM_GAP_PX)
    this.element.style.height = `${height}px`
  }
}
