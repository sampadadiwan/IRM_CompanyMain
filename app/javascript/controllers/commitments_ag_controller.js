import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  static gridOptions = {};

  static values = {
    lazyLoadData: String, // Do we want to eager or lazy load (for tabs)
    tableName: String // Which table id are we targeting
  }

  connect() {
    console.log("Hello from commitments_ag_controller.js");
    console.log(`Datatable setup for ${this.tableNameValue}`);
    
    console.log(`lazyLoadDataValue = ${this.lazyLoadDataValue}`)
    if(this.lazyLoadDataValue == "false") {
      this.init();
    }
  }

  extract_number(str_num) {
    let ret_val = Number(str_num.replace(/[^0-9.-]+/g, ""));
    return ret_val;
  }

  extract_text_from_html(html_text) {
    let ret_val = html_text.replace(/<\/?[^>]+(>|$)/g, "");
    return ret_val
  }

  format_currency(number, currency) {
    return new Intl.NumberFormat('en-US', { style: 'currency', currency: currency }).format(number);
  }

  init() {

    let columnDefs = [
      { "field": "commitment_type", headerName: "Type", filter: "agSetColumnFilter", enableRowGroup: true },
      {
        field: "folio_id", cellRenderer: this.html, headerName: "Folio", enableRowGroup: true, enablePivot: true,
        cellRenderer: function (params) {
          return params.data.folio_link;
        },
        valueGetter: (params) => { return params.data.folio_id }
      },
      {
        "field": "investor_link", cellRenderer: this.html,
        headerName: "Investor", chartDataType: 'category', enableRowGroup: true, enablePivot: true,
        cellRenderer: function (params) {
          return params.data.investor_link;
        },
        valueGetter: (params) => { return params.data.investor_name }
      },
      { "field": "full_name", cellRenderer: this.html, headerName: "Name" },
      { "field": "unit_type", headerName: "Unit Type", sortable: true, filter: "agSetColumnFilter", chartDataType: 'category', enableRowGroup: true, enablePivot: true },
      {
        "field": "committed_amount_number", headerName: "Committed",
        sortable: true, filter: 'agNumberColumnFilter', aggFunc: 'sum',
        valueFormatter: params => {
          if (params.data !== undefined) {
            return this.format_currency(params.data.collected_amount_number, params.data.fund_currency)
          }
        },
      },
      {
        "field": "percentage", headerName: "%",
        sortable: true, filter: 'agNumberColumnFilter', chartDataType: "series", aggFunc: 'sum',
        valueFormatter: params => {
          if (params.data !== undefined) {
            return `${params.data.percentage} %`;
          }
        },
      },
      {
        "field": "call_amount_number", headerName: "Called",
        sortable: true, filter: 'agNumberColumnFilter', aggFunc: 'sum',
        valueFormatter: params => {
          if (params.data !== undefined) {
            return this.format_currency(params.data.call_amount_number, params.data.fund_currency)
          }
        },
      },
      {
        "field": "collected_amount_number", headerName: "Collected",
        sortable: true, filter: 'agNumberColumnFilter', aggFunc: 'sum',
        valueFormatter: params => {
          if (params.data !== undefined) {
            return this.format_currency(params.data.collected_amount_number, params.data.fund_currency)
          }
        },
      },
      {
        "field": "distribution_amount_number", headerName: "Distributed",
        sortable: true, filter: 'agNumberColumnFilter', aggFunc: 'sum',
        valueFormatter: params => {
          if (params.data !== undefined) {
            return this.format_currency(params.data.distribution_amount_number, params.data.fund_currency)
          }
        },
      },
      { "field": "dt_actions", cellRenderer: this.html, headerName: "Actions" }
    ];


    // let the grid know which columns and what data to use
    this.gridOptions = {
      columnDefs: columnDefs,
      rowHeight: 60,
      defaultColDef: {
        flex: 1,
        resizable: true,
        filter: 'agTextColumnFilter',
        sortable: true,
      },
      enableRangeSelection: true,
      enableCharts: true,
      rowGroupPanelShow: 'always',
      suppressDragLeaveHidesColumns: true,
      suppressMakeColumnVisibleAfterUnGroup: true,
      suppressRowGroupHidesColumns: true,
      sideBar: 'columns',

    };

    // setup the grid after the page has finished loading
    var gridDiv = document.querySelector('#capital_commitments');
    new agGrid.Grid(gridDiv, this.gridOptions);
    // this.setWidthAndHeight("100%");


   this.loadData();

  }

  loadData() {
    fetch($(this.tableNameValue).data('source'))
    .then(response => response.json())
    .then(data => {
      // load fetched data into grid
      this.gridOptions.api.setRowData(data);
      console.log(data.data);
    });
  }

  setWidthAndHeight(size) {
    var eGridDiv = document.querySelector('#capital_commitments');
    eGridDiv.style.setProperty('width', size);
    eGridDiv.style.setProperty('height', size);
  }

  html(params) {
    return params.value ? params.value : '';
  }

  exportToXL() {
    this.gridOptions.api.exportDataAsExcel({
      processCellCallback(params) {
        const value = params.value;
        console.log(params);
        function extract_text_from_html(html_text) {
          let ret_val = html_text.replace(/<\/?[^>]+(>|$)/g, "");
          return ret_val
        }

        return value === undefined ? '' : extract_text_from_html(value) //`_${value}_`
      }
    });
  }

  onFilterTextBoxChanged() {
    this.gridOptions.api.setQuickFilter(
      document.getElementById('filter-text-box').value
    );
  }
}
