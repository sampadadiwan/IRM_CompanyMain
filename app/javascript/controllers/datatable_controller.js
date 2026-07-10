import { Controller } from "@hotwired/stimulus"
import { setupAccessiblePagination } from "controllers/datatable_accessibility"

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
      const controller = this;
      $.each( $('.jqDataTable'), function( key, value ) {
        // console.log( key + ": " + value );
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
          // Here we are setting up accessible search and pagination for the DataTable. This is important for users who rely on screen readers or other assistive technologies to navigate the table. The setupAccessibleSearch method adds ARIA labels and a clear button to the search input, while the setupAccessiblePagination method adds ARIA labels to the pagination controls.
          controller.setupAccessibleSearch(table[key]);
          setupAccessiblePagination(table[key]);
          table[key].on('draw.dt', () => setupAccessiblePagination(table[key]));
        }

      });

      // Use position:fixed strategy so dropdowns inside the table escape overflow clipping
      this.element.querySelectorAll('[data-bs-toggle="dropdown"]').forEach(toggle => {
        new bootstrap.Dropdown(toggle, {
          popperConfig: { strategy: 'fixed' }
        });
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

  setupAccessibleSearch(table) {

    const wrapper = $(table.table().container());

    const filter = wrapper.find('.dt-search, .dataTables_filter');

    if (!filter.length) return;

    const input = filter.find('input');

    // Keep the native type="search" (preserves the implicit ARIA searchbox role and
    // Escape-to-clear behavior); the native clear button is hidden via CSS instead.
    input.attr(
      'aria-label',
      'Search table contents'
    );
    if (!filter.find('label.datatable-search-label').length) {
      input.before(`
        <label
          class="datatable-search-label me-2"
          for="${input.attr('id')}">
          Search:
        </label>
      `);
    }
    if (filter.find('.datatable-clear-btn').length) return;

    const clearButton = $(`
      <button
        type="button"
        class="datatable-clear-btn btn btn-link p-0"
        aria-label="Clear search"
        hidden>

        <i class="ti ti-x"></i>

      </button>
    `);

    filter.append(clearButton);

    clearButton.prop('hidden', input.val().length === 0);

    input.on('input', function () {
      clearButton.prop('hidden', this.value.length === 0);
    });

    clearButton.on('click', () => {
      input.val('');

      table.search('').draw();

      clearButton.prop('hidden', true);

      input.focus();
    });
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
