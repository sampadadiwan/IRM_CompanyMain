// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {
 
  columns() {
      return [
        {"data": "folio_id"},
        {"data": "reporting_date"},
        {"data": "period"},
        {"data": "entry_type"},
        {"data": "name"},          
        {"data": "amount"},        
        {"data": "dt_actions"}
      ]
    }
}
