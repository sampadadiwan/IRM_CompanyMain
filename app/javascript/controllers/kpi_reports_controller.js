// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {
  columns() {
    return [
      {"data": "as_of"},
      {"data": "notes"},
      {"data": "user"},
      {"data": "dt_actions"}
    ]
  }
}
