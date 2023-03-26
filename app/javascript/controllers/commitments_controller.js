// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {
 
  columns() {
    if ($("#show_docs").length > 0) {
      return [
        {"data": "commitment_type"},
        {"data": "folio_id"},
        {"data": "investor_name"},
        {"data": "fund_name"},
        {"data": "unit_type"},
        {"data": "committed_amount"},
        {"data": "percentage"},
        {"data": "call_amount"},
        {"data": "collected_amount"},  
        {"data": "pending_amount"},          
        {"data": "distribution_amount"},          
        {"data": "document_names"},
        {"data": "dt_actions"}
      ]
    } else {
      return [
        {"data": "commitment_type"},
        {"data": "folio_id"},
        {"data": "investor_name"},
        {"data": "fund_name"},
        {"data": "unit_type"},
        {"data": "committed_amount"},
        {"data": "percentage"},
        {"data": "call_amount"},
        {"data": "collected_amount"},
        {"data": "pending_amount"},          
        {"data": "distribution_amount"},          
        {"data": "dt_actions"}
      ]
    }
  }
}
