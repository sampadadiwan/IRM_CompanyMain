// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {
  columns() {
    return [
      {"data": "full_name"},
      {"data": "source"},
      {"data": "created_at"},
      {"data": "dt_actions"}
    ]
  }
};
