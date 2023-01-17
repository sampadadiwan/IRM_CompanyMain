// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {
 
  columns() {
    return [
      {"data": "folio_id"},
      {"data": "investor_name"},
      {"data": "fund_name"},
      {"data": "committed_amount"},
      {"data": "percentage"},
      {"data": "collected_amount"},          
      {"data": "onboarding_completed"},
      {"data": "dt_actions"}
    ]
  }
}
