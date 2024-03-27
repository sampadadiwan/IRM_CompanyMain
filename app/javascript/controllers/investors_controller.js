// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {
  default = [
    {"data": "investor_name"},
    {"data": "pan"},
    {"data": "tag_list"},
    {"data": "category"},
    {"data": "city"},
    {"data": "access"},
    {"data": "dt_actions"}
  ]

  columns() {
    return this.default; 
  }

}
