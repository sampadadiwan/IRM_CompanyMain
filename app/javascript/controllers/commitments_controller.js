// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {
 
  columns() {
    if ($("#show_docs").length > 0) {
      return [
        {"data": "folio_id"},
        {"data": "unit_type"},
        {"data": "investor_name"},
        {"data": "fund_name"},
        {"data": "committed_amount"},
        {"data": "percentage"},
        {"data": "collected_amount"},          
        {"data": "onboarding_completed"},
        {"data": "document_names"},
        {"data": "dt_actions"}
      ]
    } else {
      return [
        {"data": "folio_id"},
        {"data": "unit_type"},
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
}
