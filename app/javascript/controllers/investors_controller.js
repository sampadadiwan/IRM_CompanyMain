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

  mobile = [
    {"data": "investor_name"},
    {"data": "pan"}
  ]

  all = [
    {"data": "investor_name"},
    {"data": "pan"},
    {"data": "tag_list"},
    {"data": "category"},
    {"data": "city"},
    {"data": "access"},
    {"data": "dt_actions"}
  ]

  columns() {

    var x = window.matchMedia("(max-width: 479px)")
    if (x.matches) { // If media query matches
      return this.mobile;
    }  
    else if($("#cols").val() == "all") {
      return this.all;
    } else {
      return this.default; 
    }
  }
}
