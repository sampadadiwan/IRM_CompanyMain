// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {
  default = [
    {"data": "investor_name"},
    {"data": "tag_list"},
    {"data": "category"},
    {"data": "city"},
    {"data": "access"},
    {"data": "dt_actions"}
  ]

  all = [
    {"data": "entity_name"},
    {"data": "investor_name"},
    {"data": "tag_list"},
    {"data": "category"},
    {"data": "city"},
    {"data": "access"},
    {"data": "dt_actions"}
  ]

  columns() {
    if($("#cols").val() == "all") {
      return this.all;
    } else {
      return this.default; 
    }
  }
}
