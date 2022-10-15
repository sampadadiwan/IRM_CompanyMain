import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {

      let table = {};
      console.log("DataTable 2.0");
      $.each( $('.jqDataTable'), function( key, value ) {
        // console.log( key + ": " + value );
        if ( $.fn.dataTable.isDataTable( value ) ) {
        }
        else {
          table[key] = $(value).DataTable({        
            stateSave: false,
            retrieve: true,
            language: {
              search: '',
              searchPlaceholder: "Search...",
              paginate: {
                "previous": "Prev"
              }          
            }
          });
  
        }
        
      });

      
      
      // Ensure DataTable is destroyed, else it gets duplicated
      $(document).on('turbo:before-cache', function() {    
        $.each( table, function( key, value ) {
          if ( $.fn.dataTable.isDataTable( value ) ) { 
            value.destroy();
          }
        });
      });
      
      let searchTerm = $("#search_term");
      if (searchTerm.length > 0) {
        table.search(searchTerm.val()).draw();
      }
  }

}
