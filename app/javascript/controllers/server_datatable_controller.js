import { Controller } from "@hotwired/stimulus"

export default class ServerDatatableController extends Controller {

  static values = {
    lazyLoadData: String, // Do we want to eager or lazy load (for tabs)
    tableName: String // Which table id are we targeting
  }

  connect() {
    console.log(`Datatable setup for ${this.tableNameValue}`);
    
    this.buildTable(this.tableNameValue);

    console.log(`lazyLoadDataValue = ${this.lazyLoadDataValue}`)
    if(this.lazyLoadDataValue == "false") {
      this.loadData();
    }
  }

  buildTable(table_id) {
    let table = null;

    if ( $.fn.dataTable.isDataTable( $(table_id) ) ) {
    }
    else {
    table = $(table_id).DataTable({
        "processing": true,
        "serverSide": true,
        "deferLoading": 0,
        stateSave: true,
        search: {
          return: true,
        },
        
        "ajax": {
          "url": $(table_id).data('source')
        },
        // "pagingType": "full_numbers",
        language: {
          search: '',
          searchPlaceholder: "Hit enter to search",
          paginate: {
            "previous": "Prev"
          }          
        },
        "columns": this.columns()
      });
    }
    

    // Ensure DataTable is destroyed, else it gets duplicated
    $(document).on('turbo:before-cache', function() {    
      if ( $.fn.dataTable.isDataTable( table ) ) { 
        table.destroy();
      }      
    });

  }

  loadData() {
    console.log("loadData called");
    let table = $(this.tableNameValue).DataTable();
    table.ajax.url( $(this.tableNameValue).data('source') ).load();
  }

  replaceQueryParam(param, newval, path) {
    var regex = new RegExp("([?;&])" + param + "[^&;]*[;&]?");
    var query = path.replace(regex, "$1").replace(/&$/, '');

    return (query.length > 2 ? query + "&" : "?") + (newval ? param + "=" + newval : '');
  }
}
