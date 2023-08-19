import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {

    let options = {
      stateSave: false,
      retrieve: true,
      language: {
        search: '',
        searchPlaceholder: "Search...",
        paginate: {
          "previous": "Prev"
        }
      }
    };

    let t1 = $("#investments-Equity").DataTable(options);
    let t2 = $("#investments-Debt").DataTable(options);

    // Ensure DataTable is destroyed, else it gets duplicated
    $(document).on('turbo:before-cache', function () {
      t2.destroy();
      t1.destroy();
    });

    // Add event listener for opening and closing details
    $('#investments-Equity tbody').on('click', 'td.dt-control', function (event) {
      let instrument = $(this).data('instrument');
      let entity = $(this).data('entity');
      let category = $(this).data('category');
      let funding_round_id = $(this).data('funding_round');
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
          url: `/holdings.json?funding_round_id=${funding_round_id}&entity_id=${entity}&investment_instrument=${instrument}&holding_type=${category}&limit=5`
        }).then(function(data) {
            console.log(data);
            row.child(format(data, category, instrument)).show();
            tr.addClass('shown');
            tr.find('svg').attr('data-icon', 'minus-circle');    // FontAwesome 5
        });

      }
    });

    function rowHtml(row, index) {
      return '<tr>'+
                '<td>'+row.funding_round_name+'</td>'+
                '<td>'+row.holder_name+'</td>'+
                '<td>'+row.investment_instrument+'</td>'+
                '<td>'+row.investment_date+'</td>'+
                '<td>'+row.quantity+'</td>'+
                '<td>'+row.price+'</td>'+
                '<td>'+row.value+'</td>'+
              '</tr>'            
    }

    function format ( data, category, instrument ) {

      let rows = "";
      for (var i = 0; i < data.length; i++) { 
        rows += rowHtml(data[i]); 
      }

      return '<div class="nested_holdings">'+
      `<span class="mb-0 text-gray-800">Top 5 ${category} ${instrument} Holdings</span>`+
      '<table class="table table-bordered dataTable">'+
          '<tr>'+
            '<th>Funding Round</th>'+
            '<th>Name</th>'+
            '<th>Instrument</th>'+
            '<th>Investment Date</th>'+
            '<th>Quantity</th>'+
            '<th>Price</th>'+
            '<th>Value</th>'+
          '</tr>'+
          rows+          
      '</table>'+
      '</div>';
    }
  

  }



};
