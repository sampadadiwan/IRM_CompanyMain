import  BaseAgGrid from "controllers/base_ag_grid"
export default class extends BaseAgGrid {

  columnDefs() {
    let controller = this;
    let html_column = this.html_column;
    let formatNumberWithCommas = this.formatNumberWithCommas;
    let numberFormatColumn = this.numberFormatColumn;
    let textColumn = this.textColumn;

    let columnDefs = [
      textColumn(controller, "buyer_entity_name", "Buyer Entity"),
      textColumn(controller, "investor_name", "Investor"),
      textColumn(controller, "user", "User"),
      numberFormatColumn(controller, "quantity", "Quantity", formatNumberWithCommas),
      numberFormatColumn(controller, "price", "Price", formatNumberWithCommas),
      numberFormatColumn(controller, "allocation_quantity", "Allocation Quantity", formatNumberWithCommas),
      numberFormatColumn(controller, "allocation_amount", "Allocation Amount", formatNumberWithCommas),
      html_column(controller, "short_listed_status", "Status"),
      html_column(controller, "escrow_deposited", "Escrow"),

      textColumn(controller, "created_at", "Created At", "sum"),
      

      { "field": "dt_actions", cellRenderer: this.html, headerName: "Actions" }
    ];

    return columnDefs;
  }

  
 
}
