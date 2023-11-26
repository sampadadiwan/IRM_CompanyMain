// import { Controller } from "@hotwired/stimulus"
import ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {

  default = [
    { "data": "folio_id" },
    { "data": "reporting_date" },
    { "data": "period" },
    { "data": "entry_type" },
    { "data": "name" },
    { "data": "amount" },
    { "data": "commitment_type" },
    { "data": "dt_actions" }
  ];

  all = [
    { "data": "fund_name" },
    { "data": "investor_name" },
    { "data": "folio_id" },
    { "data": "reporting_date" },
    { "data": "period" },
    { "data": "entry_type" },
    { "data": "name" },
    { "data": "amount" },
    { "data": "commitment_type" },
    { "data": "dt_actions" }
  ];

  columns() {
    console.log(`cols: ${$("#cols").val()}`);
    if($("#cols").val() == "all") {
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
    let url = this.replaceQueryParam("reporting_date_start", $("#reporting_date_start").val(), ds)
    url = this.replaceQueryParam("reporting_date_end", $("#reporting_date_end").val(), url)
    url = this.replaceQueryParam("cumulative", $("#cumulative").val(), url)
    url = this.replaceQueryParam("unit_type", $("#unit_type").val(), url)
    url = this.replaceQueryParam("folio_id", $("#folio_id").val(), url)
    console.log(ds);
    table.ajax.url(url).load();
  }
}
