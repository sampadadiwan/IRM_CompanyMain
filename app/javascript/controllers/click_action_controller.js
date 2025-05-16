// app/javascript/controllers/click_action_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    selector: String,
    closeOffcanvas: Boolean
  }

  perform(event) {
    event.preventDefault()

    if (this.closeOffcanvasValue) {
      const openOffcanvas = document.querySelector('.offcanvas.show')
      if (openOffcanvas) {
        const bsOffcanvas = bootstrap.Offcanvas.getInstance(openOffcanvas)
        bsOffcanvas?.hide()
      }
    }

    // Delay the target click slightly to allow the offcanvas to close
    setTimeout(() => {
      const target = document.querySelector(this.selectorValue)
      if (target) {
        target.click()
      } else {
        console.warn(`No element found for selector: '${this.selectorValue}'`)
      }
    }, 300) // 300ms delay to allow offcanvas to animate out
  }
}
