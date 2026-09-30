import { Controller } from "@hotwired/stimulus"
import { setupAccessiblePagination } from "controllers/datatable_accessibility"

// DataTables Responsive decides which columns to collapse by summing each column's
// minimum width (read via offsetWidth, i.e. rounded to whole px) and comparing that to the
// container's width. At fractional zoom levels (e.g. Chrome at 90% on Windows, where
// devicePixelRatio is 0.9 / 1.125) each rounded column width can be off by a fraction of
// a pixel, and across ~10 columns that's enough to push a table that actually fits over
// the limit — so the last column (usually the Show/Edit actions) gets folded into the
// expandable "child" row. Give each column a small tolerance only at fractional ratios.
const RESPONSIVE_ZOOM_TOLERANCE_PX = 2;

function patchResponsiveZoomTolerance() {
  const Responsive = $.fn.dataTable && $.fn.dataTable.Responsive;
  if (!Responsive || Responsive.prototype._zoomTolerancePatched) return;

  const original = Responsive.prototype._columnsVisiblity;
  Responsive.prototype._columnsVisiblity = function(breakpoint) {
    if (Number.isInteger(window.devicePixelRatio)) return original.call(this, breakpoint);

    const columns = this.s.columns;
    const saved = columns.map(col => col.minWidth);
    columns.forEach(col => {
      if (col.minWidth) col.minWidth = Math.max(col.minWidth - RESPONSIVE_ZOOM_TOLERANCE_PX, 1);
    });
    try {
      return original.call(this, breakpoint);
    } finally {
      columns.forEach((col, i) => { col.minWidth = saved[i]; });
    }
  };
  Responsive.prototype._zoomTolerancePatched = true;
}

export default class extends Controller {
  static values = {
    moneyColumns: String, // Which columns are money, so we can appply better sorting
    responsiveDetails: String, // Whether the responsive details are shown or not, default to true
    responsive: String, // set to false only if the grid should not be responsive, true by default
    restrictFocusToLinks: Boolean
  }

  connect() {

    console.log(`moneyColumns = ${this.moneyColumnsValue}`);
    console.log(`responsiveDetails = ${this.responsiveDetailsValue}`);
    console.log(`responsive = ${this.responsiveValue}`);

      patchResponsiveZoomTolerance();

      let table = {};

      let columnDefs = this.columnDefs();
      let responsive = this.responsive();
      const controller = this;
      $.each( $('.jqDataTable'), function( key, value ) {
        // console.log( key + ": " + value );
        if ( $.fn.dataTable.isDataTable( value ) ) {
        }
        else {
          // Responsive collapses columns right-to-left, so the action column (Show / Edit
          // buttons, always last) is the first to be folded behind the ▶ toggle when the
          // table is a little too wide (e.g. 110% zoom). Give it top priority so data
          // columns collapse first and the row actions stay visible.
          $(value).find('thead th.action-col:not([data-priority])').attr('data-priority', 1);
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
          controller.restrictFocusableElements(table[key]);
          table[key].on('draw.dt', () => setupAccessiblePagination(table[key]));
          table[key].on('draw.dt', () => controller.restrictFocusableElements(table[key]));
          // Paging only keeps the current page's <tr> elements in the DOM — rows for other
          // pages are detached until their page is drawn — so a one-time scan at connect()
          // misses every dropdown on pages beyond the first. Re-run it on every draw.
          table[key].on('draw.dt', () => controller.initFixedStrategyDropdowns());
          // Responsive's collapsed-column "child" row is only built (cloning cell markup,
          // buttons included) the first time it's expanded — well after the tooltip
          // controller's initial scan — so any data-bs-toggle="tooltip" buttons that landed
          // in a hidden column never got a Bootstrap Tooltip instance. Re-scan on expand.
          table[key].on('responsive-display.dt', () => controller.element.dispatchEvent(new CustomEvent('tooltip:reinit')));
          controller.scheduleRelayout(table[key]);
        }

      });

      this.initFixedStrategyDropdowns();

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

  disconnect() {
    if (this.resizeObserver) {
      this.resizeObserver.disconnect();
      this.resizeObserver = null;
    }
  }

  // Column widths (and Responsive's decision of which columns to collapse) are measured
  // once at init. On a cold load — notably Windows with fractional zoom (e.g. 90%) — that
  // can happen before web fonts / stylesheets / the sidebar have settled, leaving a broken
  // layout that only fixes itself on reload (when everything is cached). Re-measure once
  // layout settles and whenever the container is resized.
  scheduleRelayout(dt) {
    const relayout = () => {
      if (!$.fn.dataTable.isDataTable(dt.table().node())) return;
      dt.columns.adjust();
      if (dt.responsive) dt.responsive.recalc();
    };

    requestAnimationFrame(relayout);
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(relayout);
    if (document.readyState !== 'complete') window.addEventListener('load', relayout, { once: true });

    if (typeof ResizeObserver !== 'undefined') {
      let lastWidth = null;
      let frame = null;
      this.resizeObserver ||= new ResizeObserver(entries => {
        const width = Math.round(entries[0].contentRect.width);
        if (width === lastWidth) return;
        lastWidth = width;
        cancelAnimationFrame(frame);
        frame = requestAnimationFrame(() => this.relayoutCallbacks.forEach(cb => cb()));
      });
      this.relayoutCallbacks ||= [];
      this.relayoutCallbacks.push(relayout);
      this.resizeObserver.observe(this.element);
    }
  }

  // Use position:fixed strategy so dropdowns inside the table escape overflow clipping
  // from the .table-responsive wrapper (which forces overflow-y:auto once overflow-x:auto
  // is set). Guard against re-initializing dropdowns on every DataTable draw: `new
  // bootstrap.Dropdown()` only overwrites the stored instance reference, it doesn't
  // dispose the previous instance's listeners, and DataTables reuses row nodes across
  // draws (e.g. paging back to a previously visited page).
  initFixedStrategyDropdowns() {
    this.element.querySelectorAll('[data-bs-toggle="dropdown"]').forEach(toggle => {
      if (bootstrap.Dropdown.getInstance(toggle)) return;

      new bootstrap.Dropdown(toggle, {
        popperConfig: { strategy: 'fixed' }
      });
    });
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

    // Switch to type="text" to remove the browser's native clear button entirely;
    // our custom .datatable-clear-btn provides that affordance instead.
    input.attr('type', 'text');
    input.attr('role', 'searchbox');
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

  restrictFocusableElements(table) {
    if (!this.restrictFocusToLinksValue) return;

    const body = $(table.table().body());
    body.find('[tabindex]').each(function() {
      const tagName = this.tagName;
      const isLink = tagName === 'A' && this.getAttribute('href');

      if (!isLink) {
        this.setAttribute('tabindex', '-1');
      }
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
