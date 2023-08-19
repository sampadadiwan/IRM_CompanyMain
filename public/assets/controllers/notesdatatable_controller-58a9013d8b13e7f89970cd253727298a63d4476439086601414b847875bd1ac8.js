import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {

      // Setup - add a text input to each footer cell
      $('#notes-datatable tfoot th').each( function () {
          var title = $(this).text();
          $(this).html( '<input type="text" placeholder="Search '+title+'" />' );
      } );


      let table = $('#notes-datatable').dataTable({
        "processing": true,
        "serverSide": true,
        "ajax": {
          "url": $('#notes-datatable').data('source')
        },
        "pagingType": "full_numbers",
        "columns": [
          {"data": "id"},
          {"data": "user_full_name"},
          {"data": "entity_name"},
          {"data": "investor_name"},
          {"data": "details"},
          {"data": "created_at"}
        ],
        // pagingType is optional, if you want full pagination controls.
        // Check dataTables documentation to learn more about
        // available options.


        initComplete: function () {
          // Apply the search
          this.api().columns().every( function () {
              var that = this;

              $( 'input', this.footer() ).on( 'keyup change clear', function () {
                  if ( that.search() !== this.value ) {
                      that
                          .search( this.value )
                          .draw();
                  }
              } );
          } );
        }
      });
     
      // Ensure DataTable is destroyed, else it gets duplicated
      $(document).on('turbo:before-cache', function() {     
        table.destroy();
      });




      
      
  }

};
