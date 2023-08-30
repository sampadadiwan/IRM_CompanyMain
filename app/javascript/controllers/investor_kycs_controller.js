// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {

  default = [
    {"data": "investor_name"},
    {"data": "full_name"},
    {"data": "pan"},
    {"data": "pan_verified"},
    // {"data": "address"},
    // {"data": "bank_account_number"},
    // {"data": "ifsc_code"},
    {"data": "committed_amount"},
    {"data": "collected_amount"},
    {"data": "bank_verified"},
    {"data": "docs_completed"},
    {"data": "verified"},      
    {"data": "expired"},
    {"data": "dt_actions"}
  ]

  mobile = [
    {"data": "investor_name"},
    {"data": "full_name"},
    {"data": "pan"},
  ]

  columns() {
    var x = window.matchMedia("(max-width: 479px)")
    if (x.matches) { // If media query matches
      return this.mobile;
    } else {
      return this.default;
    }
  }
}
