import { Controller } from "@hotwired/stimulus"

// Make sure both XLSX (SheetJS) and x_spreadsheet are globally available
// For example, via <script src="..."> in your layout/application.html.erb

export default class extends Controller {
  static targets = ["spreadsheetContainer"]

  connect() {
    const url = this.element.dataset.url;
    if (url) {
        console.log("Loading spreadsheet from URL:", url);
    } else {
      console.error("Missing data-url on spreadsheet element");
      return;
    }

    this.loadSpreadsheet(url);
  }


  async loadSpreadsheet(url) {
    const container = this.spreadsheetContainerTarget;
  
    try {
      const response = await fetch(url);
      const arrayBuffer = await response.arrayBuffer();
      const wb = XLSX.read(arrayBuffer);
      const data = stox(wb);
      console.log("Spreadsheet loaded successfully", data);
  
      // Initialize x-spreadsheet and load data
      this.spreadsheet = new x_spreadsheet(container);
      this.spreadsheet.loadData(data);
    } catch (err) {
      console.error("Failed to load spreadsheet", err);
    }
  }



  export(event) {
    console.log("export called");

    const table_id = event.target.dataset.tableid;
    const filename = event.target.dataset.filename || 'export.xlsx';
    const table = document.getElementById(table_id);

    if (!table) {
        console.error(`Table with ID '${table_id}' not found.`);
        return;
    }

    // Clone the table to avoid modifying the original
    const clonedTable = table.cloneNode(true);

    // Regular expression to detect currency symbols (e.g., ₹, $, €, £)
    const currencyRegex = /[₹$€£]/;

    // Process each cell to remove currency symbols and convert to numbers
    const rows = clonedTable.rows;
    for (let i = 0; i < rows.length; i++) {
        const cells = rows[i].cells;
        for (let j = 0; j < cells.length; j++) {
            const cell = cells[j];
            const text = cell.textContent.trim();

            // Check if the cell contains a currency symbol
            if (currencyRegex.test(text)) {
                // Remove currency symbols and commas
                const numericText = text.replace(/[₹$€£,]/g, '').trim();

                // Convert to number if it's a valid number
                const numericValue = parseFloat(numericText);
                if (!isNaN(numericValue)) {
                    cell.textContent = numericValue;
                }
            }
        }
    }

    // Export the cleaned table
    this.exportToExcel('xlsx', clonedTable, filename);
  }

  exportToExcel(type, tableElement, filename, fn, dl) {
      if (!tableElement) {
          console.error('No table element provided for export.');
          return;
      }

      const wb = XLSX.utils.table_to_book(tableElement, { sheet: "sheet1" });
      return dl
          ? XLSX.write(wb, { bookType: type, bookSST: true, type: 'base64' })
          : XLSX.writeFile(wb, fn || `${filename}.${type || 'xlsx'}`);
  }

  
}
