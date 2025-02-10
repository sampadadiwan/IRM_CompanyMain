import  BaseAgGrid from "controllers/base_ag_grid"
export default class extends BaseAgGrid {

  columnDefs() {
    let controller = this;
    let columnDefs = [
      { "field": "fund_name", headerName: "Fund", filter: "agSetColumnFilter", enableRowGroup: true },
      {
        field: "folio_id", headerName: "Folio", enableRowGroup: true, enablePivot: true,
        cellRenderer: function (params) {
          return controller.renderCell(params, "folio_link", "folio_id");
        },
        valueGetter: (params) => { 
          if (params.data !== undefined) {
            return params.data.folio_id 
          } 
        }
      },
      {
        "field": "investor_link", 
        headerName: "Investor", chartDataType: 'category', enableRowGroup: true, enablePivot: true,
        cellRenderer: function (params) {
          return controller.renderCell(params, "investor_link");
        },
        valueGetter: (params) => { 
          if (params.data !== undefined) {
            return params.data.investor_name 
          } 
        },
      },
      { "field": "full_name", cellRenderer: this.html, headerName: "Name" },
      { "field": "unit_type", headerName: "Unit Type", sortable: true, filter: "agSetColumnFilter", chartDataType: 'category', enableRowGroup: true, enablePivot: true },
      {
        "field": "committed_amount_number", headerName: "Committed",
        sortable: true, filter: 'agNumberColumnFilter', aggFunc: 'sum',         
        valueFormatter: params => {
          // console.log(params.data.committed_amount_number);
          if (params.data !== undefined) {
            return this.format_currency(params.data.committed_amount_number, params.data.fund_currency)
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

    return columnDefs;
  }

  

 
}
