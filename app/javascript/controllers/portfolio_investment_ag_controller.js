import  BaseAgGrid from "controllers/base_ag_grid"
export default class extends BaseAgGrid {

  columnDefs() {
    const controller = this;
    const html_column = this.html_column;
    const formatNumberWithCommas = this.formatNumberWithCommas;
    const numberFormatColumn = this.numberFormatColumn;
    const dateFormatColumn = this.dateFormatColumn;
    const textColumn = this.textColumn;
    const snakeToHuman = this.snakeToHuman;

    const customColumns = JSON.parse(document.getElementsByClassName("portfolio_investment_ag_grid")[0].dataset.customColumns)

    let columnDefs = [];
    console.log(customColumns)
    customColumns.forEach((column) => {
      const { key, label, data_type } = column;

      if (data_type === "String") {
        columnDefs.push(textColumn(controller, key, label));
      } else if (data_type === "Date") {
          columnDefs.push(dateFormatColumn(controller, key, label));
      } else if (data_type === "Number" || data_type === "Decimal") {
        columnDefs.push(numberFormatColumn(controller, key, label, formatNumberWithCommas));
      } else if (data_type === "Html" || data_type === "Boolean") {
        columnDefs.push(html_column(controller, key, label));
      } else {
        columnDefs.push(textColumn(controller, key, label));
      }
    });

    columnDefs.push(textColumn(controller, "created_at", "Created At"));
    columnDefs.push({
      field: "dt_actions",
      cellRenderer: this.html,
      headerName: "Actions",
    });

    return columnDefs;
  }



  restoreGrouping() {
    // Programmatically restore grouping
    this.gridOptions.columnApi.setRowGroupColumns(['portfolio_company_name']);
  }

  
 
}
