// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {
  columns() {
    // Check the value of fund_ratios_show_funds hidden field
    // If true, then show the fund_name column
    // If false, then hide the fund_name column
    let show_columns = $('#fund_ratios_show_columns').val();
    // Check if show_columns is not empty
    if (show_columns) {
      // Split the string into an array
      let columns = show_columns.split(',');
      // Map the array to an array of objects
      return columns.map(column => {
        return {"data": column}
      });
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
