// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {
 
  columns() {
    return [
      {"data": "investor_name"},
      {"data": "folio_id"},
      {"data": "amount"},
      {"data": "payment_date"},          
      {"data": "completed"},
      {"data": "dt_actions"}
    ]
  }
};
