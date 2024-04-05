import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {

    let options = {
      stateSave: true,
      retrieve: true,
      language: {
        search: '',
        searchPlaceholder: "Search...",
        paginate: {
        }
      }
    };

    let t1 = $("#aggregate_investments").DataTable(options);
    
    // Ensure DataTable is destroyed, else it gets duplicated
    $(document).on('turbo:before-cache', function () {
      t1.destroy();
    });


    // Add event listener for opening and closing details
    $('#aggregate_investments tbody').on('click', 'td.dt-control', function (event) {
      let entity = $(this).data('entity');
      let investor_id = $(this).data('investor');
      let funding_round_id = $(this).data('funding-round');
      var tr = $(this).closest('tr');
      var row = t1.row(tr);

      if (row.child.isShown()) {
        // This row is already open - close it
        row.child.hide();
        tr.removeClass('shown');
        tr.find('svg').attr('data-icon', 'plus-circle');    // FontAwesome 5
      }
      else {

        $.ajax({
          url: `/investments.json?entity_id=${entity}&investor_id=${investor_id}&funding_round_id=${funding_round_id}&equity_like=true`
        }).then(function(data) {
            console.log(data);
            row.child(format(data)).show();
            tr.addClass('shown');
            tr.find('svg').attr('data-icon', 'minus-circle');    // FontAwesome 5
        });

      }
    });

    function rowHtml(row, index) {
      return '<tr>'+
                '<td>'+row.category+'</td>'+
                '<td>'+row.funding_round+'</td>'+
                '<td>'+row.investor_name+'</td>'+
                '<td>'+row.investment_instrument+'</td>'+                
                '<td>'+row.investment_date+'</td>'+
                '<td>'+row.quantity+'</td>'+
                '<td>'+row.percentage_holding+'</td>'+
                '<td>'+row.diluted_percentage+'</td>'+
                '<td>'+row.price+'</td>'+
                '<td>'+row.amount+'</td>'+
              '</tr>'            
    }

    function format ( data ) {

      let rows = "";
      for (var i = 0; i < data.length; i++) { 
        rows += rowHtml(data[i]); 
      }

      return '<div class="nested_holdings">'+
      `<span class="mb-0 text-gray-800">Investments</span>`+
      '<table class="table table-bordered table-striped dataTable">'+
          '<tr>'+
            '<th>Category</th>'+
            '<th>Funding Round</th>'+
            '<th>Investor</th>'+
            '<th>Instrument</th>'+
            '<th>Investment Date</th>'+
            '<th>Quantity</th>'+
            '<th>Percent Holding</th>'+
            '<th>Fully Diluted</th>'+
            '<th>Price</th>'+
            '<th>Amount</th>'+
          '</tr>'+
          rows+          
      '</table>'+
      '</div>';
    }
  

  }



}
