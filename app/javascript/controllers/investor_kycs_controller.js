// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {

  columns() {
    return [
      {"data": "investor_name"},
      {"data": "full_name"},
      {"data": "pan"},
      {"data": "pan_verified"},
      {"data": "address"},
      // {"data": "bank_account_number"},
      // {"data": "ifsc_code"},
      {"data": "committed_amount"},
      {"data": "collected_amount"},
      {"data": "bank_verified"},
      {"data": "verified"},
      {"data": "expired"},
      {"data": "dt_actions"}
    ]
  }
}
