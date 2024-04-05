import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    moneyColumns: String, // Which columns are money, so we can appply better sorting
    responsiveDetails: String, // Whether the responsive details are shown or not, default to true
    responsive: String // set to false only if the grid should not be responsive, true by default
  }

  connect() {

    console.log(`moneyColumns = ${this.moneyColumnsValue}`);
    console.log(`responsiveDetails = ${this.responsiveDetailsValue}`);
    console.log(`responsive = ${this.responsiveValue}`);

      let table = {};
      
      let columnDefs = this.columnDefs();
      let responsive = this.responsive();      
      $.each( $('.jqDataTable'), function( key, value ) {
        console.log( key + ": " + value );
        if ( $.fn.dataTable.isDataTable( value ) ) {
        }
        else {
          table[key] = $(value).DataTable({    
            order: [],     
            stateSave: false,
            retrieve: true,
            responsive: responsive,  
            // columnDefs: columnDefs, // https://cdn.datatables.net/plug-ins/2.0.2/sorting/formatted-numbers.js      
            lengthMenu: [
              [10, 25, 50, -1],
              [10, 25, 50, 'All'],
            ],
            language: {
              search: '',
              searchPlaceholder: "Search...",
              paginate: {
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

  responsive() {
    // Sometimes we dont wnat the grid to be responsive e.x. deals screen
    let responsive = null;
    let responsiveDetails = false;
    if (this.responsiveValue.length == 0 || this.responsiveValue == "true") {          
      // Setup whether the responsive details are shown or not, default to true
      responsiveDetails = true;
      if(this.responsiveDetailsValue.length > 0) {
        responsiveDetails = this.responsiveDetailsValue == "true";
      }
      responsive = {
        details: responsiveDetails
      }
    }

    return responsive;
  }


  columnDefs() {
    if (this.moneyColumnsValue == "") {
      return [];
    } else {
      // Convert the string to an array of integers
      let moneyColumns = this.moneyColumnsValue.split(',');
      // Convert the array of integers to an array of columnDefs, which is used by cdn.datatables.net/plug-ins/2.0.2/sorting/formatted-numbers.js, to allow the right formatting for currency cols
      let cols = moneyColumns.map(function(item) {
        return { type: 'formatted-num', targets: parseInt(item) }
      });
      // console.log(cols);
      return cols;
    }
  }

}
