import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "indicator"]
  static values = { url: String }

  connect() {
    this.setupEditable()
  }

  setupEditable() {
    // We make the whole container editable, but stop propagation for Reveal.js
    this.containerTarget.setAttribute("contenteditable", "true")

    this.containerTarget.addEventListener("keydown", (e) => {
      // Allow standard editing keys but stop Reveal.js from seeing them
      // especially arrows, space, etc. which Reveal uses for navigation
      const keysToProtect = ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", " ", "Home", "End"]
      if (keysToProtect.includes(e.key)) {
        e.stopPropagation()
      }
    }, true)
  }

  handleInput() {
    this.save()
  }

  save() {
    if (this.indicatorTarget) {
      this.indicatorTarget.innerText = "Saving..."
      this.indicatorTarget.classList.remove("opacity-0")
    }

    clearTimeout(this.saveTimeout)
    this.saveTimeout = setTimeout(() => {
      this.performSave()
    }, 1500)
  }

  async performSave() {
    const html = this.containerTarget.innerHTML

    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCsrfToken()
        },
        body: JSON.stringify({ content_html: html })
      })

      if (response.ok) {
        if (this.indicatorTarget) {
          this.indicatorTarget.innerText = "Saved"
          setTimeout(() => {
            this.indicatorTarget.classList.add("opacity-0")
          }, 2000)
        }
      } else {
        if (this.indicatorTarget) {
          this.indicatorTarget.innerText = "Error"
        }
      }
    } catch (error) {
      console.error("Error saving slides:", error)
      if (this.indicatorTarget) {
        this.indicatorTarget.innerText = "Error"
      }
    }
  }

  getCsrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }
}
