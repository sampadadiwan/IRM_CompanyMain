// import { Controller } from "@hotwired/stimulus"
import ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {


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

  // finalizeTable() {    
  //   var x = window.matchMedia("(max-width: 479px)")
  //   console.log("account_entries_controller finalizeTable called");
  //   let table = $(this.tableNameValue).DataTable();
      
  //   if($("#account_entry_cols").val() == "all") {
  //     table.column(0).visible(true);
  //   } else {
  //     table.column(0).visible(false);
  //   }
  // }
}
