import  BaseAgGrid from "controllers/base_ag_grid"
export default class extends BaseAgGrid {

  columnDefs() {
    let controller = this;
    let columnDefs = [
      { "field": "fund_name", headerName: "Fund", filter: "agSetColumnFilter", enableRowGroup: true, enablePivot: true, chartDataType: 'category', },

      {
        field: "name", headerName: "Name", enableRowGroup: true, enablePivot: true,
        cellRenderer: function (params) {
          return controller.renderCell(params, "name_link", "name");
        },
        valueGetter: (params) => { 
          if (params.data !== undefined) {
            return params.data.name 
          }
        }
      },

      { "field": "entry_type", headerName: "Entry Type", filter: "agSetColumnFilter", enableRowGroup: true, enablePivot: true, chartDataType: 'category', },
      { "field": "unit_type", headerName: "Unit Type", filter: "agSetColumnFilter", enableRowGroup: true, enablePivot: true, chartDataType: 'category', },
      { "field": "reporting_date", headerName: "Date", filter: "agDateColumnFilter", enableRowGroup: true, enablePivot: true, chartDataType: 'category', },
      { "field": "period", headerName: "Period", filter: "agSetColumnFilter", enableRowGroup: true, enablePivot: true, chartDataType: 'category', },
      
      {
        field: "folio_id", headerName: "Folio", enableRowGroup: true, enablePivot: true, chartDataType: 'category',
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
        "field": "amount_number", headerName: "Amount",
        sortable: true, filter: 'agNumberColumnFilter', aggFunc: 'sum',
        valueFormatter: params => {
          if (params.data !== undefined) {
            if(params.data.name.includes("Percentage")) {
              return `${params.data.amount_cents} %`;
            } else {
              return this.format_currency(params.data.amount_number, params.data.fund_currency);
            }
          }
        },
      },

      { "field": "dt_actions", cellRenderer: this.html, headerName: "Actions" }
    ];

    return columnDefs;
  }

  
  includeFooter() {
    return false;
  }

  includeTotalFooter() {
      return false;
  }
 
}
