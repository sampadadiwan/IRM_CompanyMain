import  BaseAgGrid from "controllers/base_ag_grid"
export default class extends BaseAgGrid {

  columnDefs() {
    
    let columnDefs = [
      
      {
        field: "name", headerName: "Name", enableRowGroup: true, enablePivot: true,
        cellRenderer: function (params) {
          if (params.data !== undefined) {
            return params.data.name_link;
          }
        },
        valueGetter: (params) => { 
          if (params.data !== undefined) {
            return params.data.name 
          }
        }
      },

      { "field": "entry_type", headerName: "Entry Type", filter: "agSetColumnFilter", enableRowGroup: true, chartDataType: 'category', },
      { "field": "reporting_date", headerName: "Date", filter: "agDateColumnFilter", enableRowGroup: true, chartDataType: 'category', },
      { "field": "period", headerName: "Period", filter: "agSetColumnFilter", enableRowGroup: true, chartDataType: 'category', },
      
      {
        field: "folio_id", headerName: "Folio", enableRowGroup: true, enablePivot: true, chartDataType: 'category',
        cellRenderer: function (params) {
          if (params.data !== undefined) {
            return params.data.folio_link;
          }
        },
        valueGetter: (params) => { 
          if (params.data !== undefined) {
            return params.data.folio_id 
          }
        }
      },

      {
        "field": "amount_number", headerName: "Amount",
        sortable: true, filter: 'agNumberColumnFilter', aggFunc: 'sum',
        valueFormatter: params => {
          if (params.data !== undefined) {
            return this.format_currency(params.data.amount_number, params.data.fund_currency)
          }
        },
      },

      { "field": "dt_actions", cellRenderer: this.html, headerName: "Actions" }
    ];

    return columnDefs;
  }

  

 
}
