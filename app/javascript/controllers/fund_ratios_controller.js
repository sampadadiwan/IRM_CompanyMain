// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {
  columns() {
    return [

      {"data": "owner_name"},
      {"data": "name"},
      {"data": "display_value"},
      {"data": "created_at"},
      {"data": "dt_actions"}
    ]
  }
}
