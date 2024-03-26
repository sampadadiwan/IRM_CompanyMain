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

  finalzeTable() {    
    var x = window.matchMedia("(max-width: 479px)")
    console.log("investors_controller finalizeTable called");
    let table = $(this.tableNameValue).DataTable();
      
    if (x.matches) { // If media query matches
      for (var i = 2; i < this.default.length; i++) {
        table.column(i).visible(false);
      }
    } else {
      for (var i = 2; i < this.default.length; i++) {
        table.column(i).visible(true);
      }
    }
  }
}
