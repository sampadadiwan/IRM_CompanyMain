import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  static gridOptions = {};

  connect() {
    console.log("Hello from commitments_ag_controller.js");
    this.init();
  }

  extract_number(str_num) {
    let ret_val = Number(str_num.replace(/[^0-9.-]+/g,""));
    return ret_val
  }
  

  init() {

    let columnDefs = [
      {"field": "commitment_type", headerName: "Type", filter: "agSetColumnFilter", enableRowGroup: true},
      {field: "folio_id", cellRenderer: this.html, headerName: "Folio"},
      {"field": "investor_name", cellRenderer: this.html, headerName: "Investor", chartDataType: 'category'},
      {"field": "full_name", cellRenderer: this.html, headerName: "Name"},
      {"field": "unit_type", headerName: "Unit Type", sortable: true, filter: "agSetColumnFilter", chartDataType: 'category', enableRowGroup: true, enablePivot: true },
      {"field": "committed_amount", headerName: "Committed", sortable: true, filter: 'agNumberColumnFilter', aggFunc: 'sum', valueGetter: (params) => { return parseInt(params.data.committed_amount) }},
      {"field": "percentage", headerName: "%", sortable: true, filter: 'agNumberColumnFilter', chartDataType: "series", aggFunc: 'sum', valueGetter: (params) => { return parseInt(params.data.percentage) }},
      {"field": "call_amount", headerName: "Called", sortable: true, filter: 'agNumberColumnFilter', filterValueGetter: (params) => { return this.extract_number(params.data.call_amount) }},
      {"field": "collected_amount", headerName: "Collected", sortable: true, filter: 'agNumberColumnFilter', filterValueGetter: (params) => { return this.extract_number(params.data.collected_amount) }},
      {"field": "distribution_amount", headerName: "Distributed", sortable: true, filter: 'agNumberColumnFilter', filterValueGetter: (params) => { return this.extract_number(params.data.distribution_amount) }},          
      {"field": "dt_actions", cellRenderer: this.html, headerName: "Actions"}
    ];
   
    
    // let the grid know which columns and what data to use
    this.gridOptions = {
      columnDefs: columnDefs,
      rowHeight: 60,
      defaultColDef: {
        flex: 1,
        minWidth: 150,
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


    fetch("/capital_commitments.json")
   .then(response => response.json())
   .then(data => {
      // load fetched data into grid
      this.gridOptions.api.setRowData(data.data);
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
