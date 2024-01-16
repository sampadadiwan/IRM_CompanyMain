import { Controller } from "@hotwired/stimulus"

export default class ServerDatatableController extends Controller {

  static values = {
    lazyLoadData: String, // Do we want to eager or lazy load (for tabs)
    tableName: String, // Which table id are we targeting
    fieldList: String, // Which fields are we targeting
    mobileFieldList: String // Which fields are we targeting
  }

  connect() {
    console.log(`Datatable setup for ${this.tableNameValue}`);
    console.log(`lazyLoadDataValue = ${this.lazyLoadDataValue}`);
    console.log(`fieldListValue = ${this.fieldListValue}`);
    console.log(`mobileFieldListValue = ${this.mobileFieldListValue}`);
    
    this.buildTable(this.tableNameValue);

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
          // return: true,
        },
        
        "ajax": {
          "url": $(table_id).data('source')
        },
        // "pagingType": "full_numbers",
        language: {
          search: '',
          searchPlaceholder: "Search...",
          paginate: {
            "previous": "Prev"
          }          
        },
        "columns": this.columns(),
        "initComplete": function() 
        {
          console.log(`Testing initComplete ${table_id}`);
         $(`${table_id}_filter input`)
          .unbind() // Unbind previous default bindings
          .bind("input", function(e) { // Bind our desired behavior
              // If the length is 3 or more characters, or the user pressed ENTER, search
              if(this.value.length >= 3 || e.keyCode == 13) {
                  // Call the API search function
                  table.search(this.value).draw();
              }
              // Ensure we clear the search if they backspace far enough
              if(this.value == "") {
                table.search("").draw();
              }
              return;
          });
          
        }
      });
    }
    

    // Ensure DataTable is destroyed, else it gets duplicated
    $(document).on('turbo:before-cache', function() {    
      if ( $.fn.dataTable.isDataTable( table ) ) { 
        table.destroy();
      }      
    });

  }

  columns() {    
    let cols = this.customColumns();
    console.log("cols", cols);  
    return cols;
  }

  customColumns() {
    let fields = this.fieldListValue.split(",");
    var x = window.matchMedia("(max-width: 479px)")
    if (x.matches) { // If media query matches
      if(this.mobileFieldListValue) {
        fields = this.mobileFieldListValue.split(",")
      } else {
        fields = fields.slice(0,3);
      }
    } 
    
    if (this.fieldListValue == "") {
      return [];
    } else  {
      return fields.map(function(item) {
        return {"data": item};
      });
    }    
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
