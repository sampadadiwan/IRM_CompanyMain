// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {
 
  default = [
    {"data": "commitment_type"},
    {"data": "folio_id"},
    {"data": "investor_name"},
    {"data": "full_name"},
    {"data": "unit_type"},
    {"data": "committed_amount"},
    {"data": "percentage"},
    {"data": "call_amount"},
    {"data": "collected_amount"},
    {"data": "distribution_amount"},          
    {"data": "dt_actions"}
  ];

  all = [
    {"data": "fund_name"},
    {"data": "commitment_type"},
    {"data": "folio_id"},
    {"data": "investor_name"},
    {"data": "full_name"},
    {"data": "unit_type"},
    {"data": "committed_amount"},
    {"data": "percentage"},
    {"data": "call_amount"},
    {"data": "collected_amount"},
    {"data": "distribution_amount"},          
    {"data": "dt_actions"}
  ];

  with_docs = [
    {"data": "commitment_type"},
    {"data": "folio_id"},
    {"data": "investor_name"},
    {"data": "full_name"},
    {"data": "unit_type"},
    {"data": "committed_amount"},
    {"data": "percentage"},
    {"data": "call_amount"},
    {"data": "collected_amount"},  
    {"data": "distribution_amount"},          
    {"data": "document_names"},
    {"data": "dt_actions"}
  ];


  columns() {
    if ($("#show_docs").length > 0) {
      return this.with_docs;
    } else {
      if($("#commitment_cols").val() == "all") {
        return this.all;
      } else {
        return this.default; 
      }
    }
  }
}
