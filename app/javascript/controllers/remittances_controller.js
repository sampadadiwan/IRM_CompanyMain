// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {

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
