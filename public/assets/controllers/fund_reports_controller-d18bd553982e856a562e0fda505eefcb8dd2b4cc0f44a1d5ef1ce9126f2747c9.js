// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {
  
  columns() {
      return [
        {"data": "name"},
        {"data": "name_of_scheme"},
        {"data": "start_date"},
        {"data": "end_date"},
        {"data": "dt_actions"}
      ]
    }
};
