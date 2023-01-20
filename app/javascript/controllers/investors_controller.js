// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {
 
  columns() {
    return [
      {"data": "investor_name"},
      {"data": "tag_list"},
      {"data": "category"},
      {"data": "city"},
      {"data": "access"},
      {"data": "dt_actions"}
    ]
  }
}
