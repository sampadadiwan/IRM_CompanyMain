// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {
  columns() {
    return [
      {"data": "as_of"},
      {"data": "period"},
      {"data": "notes"},
      {"data": "user"},
      {"data": "entity"},
      {"data": "dt_actions"}
    ]
  }
}
