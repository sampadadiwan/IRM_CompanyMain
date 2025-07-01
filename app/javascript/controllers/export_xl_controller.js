import { Controller } from "@hotwired/stimulus"

// XLSX must be available globally, e.g., via a <script> tag or import map
export default class extends Controller {

    connect() {
        console.log("Export XL");
    }

    export(event) {
        console.log("export called");

        const tableId = event.target.dataset.tableid;
        const filename = event.target.dataset.filename ? `${event.target.dataset.filename}.xlsx` : 'export.xlsx';
        const table = document.getElementById(tableId);

        if (!table) {
            console.error(`Table with id '${tableId}' not found.`);
            return;
        }

        // Clone the table to avoid modifying the original
        const clonedTable = table.cloneNode(true);
        this.cleanCurrencyCells(clonedTable);

        this.exportToExcel('xlsx', clonedTable, filename);
    }

    cleanCurrencyCells(clonedTable) {
        const currencyRegex = /[₹$€£]/;

        const rows = clonedTable.rows;
        for (let i = 0; i < rows.length; i++) {
            const cells = rows[i].cells;
            for (let j = 0; j < cells.length; j++) {
                const cell = cells[j];
                const text = cell.textContent.trim();

                // Check if the cell contains a currency symbol
                if (currencyRegex.test(text)) {
                    const numericText = text.replace(/[₹$€£,]/g, '').trim();
                    const numericValue = parseFloat(numericText);
                    if (!isNaN(numericValue)) {
                        cell.textContent = numericValue;
                    }
                }
            }
        }
    }

    exportToExcel(type, tableElement, filename, fn, dl) {
        const ws = XLSX.utils.aoa_to_sheet([]);
        let R = 0;
        let maxC = 0;

        for (let i = 0; i < tableElement.rows.length; i++) {
            const row = tableElement.rows[i];
            let C = 0;
            for (let j = 0; j < row.cells.length; j++) {
                const cell = row.cells[j];
                const text = cell.innerText.trim();
                const link = cell.querySelector('a');
                const value = parseFloat(text);
                const isNumber = !isNaN(value) && !text.includes(':'); // crude check to avoid time-like strings

                const cellObj = isNumber ? { v: value, t: 'n' } : { v: text };
                if (link && link.href) {
                    cellObj.l = { Target: link.href };
                }

                const cellAddress = XLSX.utils.encode_cell({ r: R, c: C });
                ws[cellAddress] = cellObj;
                C++;
            }
            if (C > maxC) maxC = C;
            R++;
        }

        ws['!ref'] = XLSX.utils.encode_range({ s: { r: 0, c: 0 }, e: { r: R - 1, c: maxC - 1 } });

        const wb = XLSX.utils.book_new();
        XLSX.utils.book_append_sheet(wb, ws, "Sheet1");

        return dl ?
            XLSX.write(wb, { bookType: type, bookSST: true, type: 'base64' }) :
            XLSX.writeFile(wb, fn || filename);
    }
}
