import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["investmentType", "convertibleFields"]

  connect() {
    console.log("Investment Form Controller Connected")
    this.toggleFields()
    this.setupSelect2Listener()
  }

  setupSelect2Listener() {
    $(this.investmentTypeTarget).on('select2:select', () => {
      console.log("Select2 selected (Investment Type)")
      this.toggleFields()
    })
  }

  toggleFields() {
    const value = this.investmentTypeTarget.value
    console.log("Investment Type Value:", value)

    if (value === "Convertible") {
      console.log("Showing convertible fields")
      this.convertibleFieldsTarget.classList.remove("d-none")
      this.convertibleFieldsTarget.style.display = "block"
    } else {
      console.log("Hiding convertible fields")
      this.convertibleFieldsTarget.classList.add("d-none")
      this.convertibleFieldsTarget.style.display = "none"
    }
  }

  disconnect() {
    $(this.investmentTypeTarget).off('select2:select')
  }
}
