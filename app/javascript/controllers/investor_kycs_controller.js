// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {
  static targets = ["select"]

  connect() {
    // Initialize Select2 on the <select> element
    this.initializeSelect2()
  }

  disconnect() {
    // Clean up when navigating away
    $(this.selectTarget).select2("destroy")
  }

  initializeSelect2() {
    const el = this.selectTarget

    // Listen for the internal state change and re-dispatch a native `change`
    $(el).on("select2:select select2:unselect clear", () => {
      el.dispatchEvent(new Event("change", { bubbles: true }))
    })
  }

  kyc_type_changed(event) {
    let kyc_type = $('#kyc_type').val();
    console.log("kyc_type", kyc_type);

    let href = new URL(window.location.href);
    href.searchParams.set('kyc_type', kyc_type);
    console.log(href.toString());

    window.location.href = href.toString();
  } 

  investor_selected(event) {
    // Selec the display value not the id 
    let selectedOption = event.target.options[event.target.selectedIndex];
    console.log("selectedOption", selectedOption);
    // Set the full name input field with the selected option's text, only if the kyc type is individual
    $("#individual_kyc_full_name").val(selectedOption.text);
  }
  
}
