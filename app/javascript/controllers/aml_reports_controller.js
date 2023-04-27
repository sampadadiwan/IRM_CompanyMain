// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {
  columns() {
    return [

      {"data": "name"},
      {"data": "match_status"},
      {"data": "approved"},
      {"data": "types"},
      {"data": "associates"},
      {"data": "dt_actions"}
    ]
  }
}
