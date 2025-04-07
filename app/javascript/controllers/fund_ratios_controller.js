// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {
  columns() {
    // Check the value of fund_ratios_show_funds hidden field
    // If true, then show the fund_name column
    // If false, then hide the fund_name column
    let show_funds = $('#fund_ratios_show_funds').val();
    if (show_funds == "true") {
      return [
        {"data": "fund_name"},
        {"data": "owner_name"},
        {"data": "owner_type"},
        {"data": "name"},
        {"data": "display_value"},
        {"data": "end_date"},
        {"data": "scenario"},
        {"data": "dt_actions"}
      ]
    } else {
      return [
        {"data": "owner_name"},
        {"data": "owner_type"},
        {"data": "name"},
        {"data": "display_value"},
        {"data": "end_date"},
        {"data": "scenario"},
        {"data": "dt_actions"}
      ]
    }
  }
}
