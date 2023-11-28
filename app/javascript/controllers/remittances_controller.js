// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {

  default = [
    {"data": "investor_name"},
    {"data": "capital_call_name"},
    {"data": "folio_id"},
    {"data": "status"},
    {"data": "created_by"},
    {"data": "verified", "className": "verified"},
    {"data": "due_amount", sortable: false},
    {"data": "collected_amount"},
    {"data": "payment_date"},
    {"data": "dt_actions"}
  ];


  all = [
    {"data": "fund_name"},
    {"data": "investor_name"},
    {"data": "capital_call_name"},
    {"data": "folio_id"},
    {"data": "status"},
    {"data": "created_by"},
    {"data": "verified", "className": "verified"},
    {"data": "due_amount", sortable: false},
    {"data": "collected_amount"},
    {"data": "payment_date"},
    {"data": "dt_actions"}
  ];


  columns() {
    if($("#capital_remittance_cols").val() == "all") {
      return this.all;
    } else {
      return this.default;
    }
  }

  filterData(event) {
    console.log("filterData called");
    let table = $(this.tableNameValue).DataTable();
    let ds = $(this.tableNameValue).data('source');
    console.log(ds);
    let url = this.replaceQueryParam("status", $("#status").val(), ds)
    url = this.replaceQueryParam("verified", $("#verified").val(), url)
    table.ajax.url( url ).load();
  }


}
