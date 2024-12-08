import  BaseAgGrid from "controllers/base_ag_grid"
export default class extends BaseAgGrid {

  columnDefs() {
    let controller = this;
    let html_column = this.html_column;
    let formatNumberWithCommas = this.formatNumberWithCommas;
    let numberFormatColumn = this.numberFormatColumn;
    let textColumn = this.textColumn;

    let columnDefs = [
      textColumn(controller, "portfolio_company_name", "Portfolio Company", "", true, true, true),
      textColumn(controller, "instrument_name", "Instrument"),
      textColumn(controller, "investment_date", "Investment Date"),
      numberFormatColumn(controller, "amount", "Amount", formatNumberWithCommas),
      numberFormatColumn(controller, "quantity", "Quantity", formatNumberWithCommas),
      numberFormatColumn(controller, "cost_per_share", "Cost Per Share", formatNumberWithCommas),
      numberFormatColumn(controller, "fmv", "FMV", formatNumberWithCommas),
      numberFormatColumn(controller, "cost_of_sold", "FIFO Cost", formatNumberWithCommas),
      html_column(controller, "notes", "Notes")
    ];

    let snakeToHuman = this.snakeToHuman;
    // Add custom fields if any
    if (this.customFieldsValue) {
      let customFields = this.customFieldsValue.split(",");
      customFields.forEach(function (field) {
        columnDefs.push(textColumn(controller, field, snakeToHuman(field)));
      });
    }

    // Finally push the created at
    columnDefs.push(textColumn(controller, "created_at", "Created At"));
    columnDefs.push({ "field": "dt_actions", cellRenderer: this.html, headerName: "Actions" });
    

    return columnDefs;
  }


  restoreGrouping() {
    // Programmatically restore grouping
    this.gridOptions.columnApi.setRowGroupColumns(['portfolio_company_name']);
  }

  
 
}
