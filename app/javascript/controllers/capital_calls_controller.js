import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {
 
  columns() {
    return [
      {"data": "fund_name"},
      {"data": "name"},
      {"data": "commitment_type"},
      {"data": "due_date"},
      {"data": "call_amount"},
      {"data": "collected_amount"},
      {"data": "due_amount", orderable: false},          
      {"data": "approved"},
      {"data": "dt_actions"}
    ]
  }

}
