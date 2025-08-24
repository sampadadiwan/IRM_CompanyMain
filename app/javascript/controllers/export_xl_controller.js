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

    /**
     * Return a SheetJS cell object built from the cell’s text.
     *  • Converts only *pure* numbers (digits, optional commas, decimals, minus sign).
     *  • Leaves anything that contains letters untouched.
     *  • Handles blanks and “-” placeholders.
     */
    buildCell(text, link) {
        const raw = text.trim();

        // treat empty or dash as blank
        if (raw === "" || raw === "-") return { v: "" };

        // quick sanity check: if the string has any letter, keep it as text
        if (/[A-Za-z]/.test(raw)) return { v: raw };

        // still here? looks numeric-ish – strip thousands separators & symbols
        const cleaned = raw.replace(/[^0-9.\-]/g, "");
        const num = cleaned ? Number(cleaned) : NaN;

        if (!Number.isNaN(num)) {
            const obj = { v: num, t: "n", z: "#,##0.00" };
            if (link) obj.l = { Target: link.href };
            return obj;
        }

        // fallback – leave as text
        return { v: raw };
    }


    exportToExcel(type, tableElement, filename) {
        const ws = this.exportTableToSheet(tableElement);
        const wb = XLSX.utils.book_new();
        XLSX.utils.book_append_sheet(wb, ws, "Sheet1");
        XLSX.writeFile(wb, filename);
    }

    exportTableToSheet(tableElement) {
        const ws = {};
        const data = [];
        const merges = [];
        const R = tableElement.rows.length;
        let maxC = 0; // Initialize maxC here

        // Create a virtual grid to handle merged cells
        const grid = [];
        for (let i = 0; i < R; i++) {
            grid[i] = [];
            // Initialize with a reasonable number of columns, will expand if needed
            for (let j = 0; j < 200; j++) {
                grid[i][j] = { occupied: false, value: null, link: null };
            }
        }

        let rowIdx = 0;
        for (const row of tableElement.rows) {
            let colIdx = 0;
            for (const cell of row.cells) {
                // Find the next available cell in the grid
                while (grid[rowIdx][colIdx] && grid[rowIdx][colIdx].occupied) {
                    colIdx++;
                }

                const rowspan = parseInt(cell.rowSpan || 1, 10);
                const colspan = parseInt(cell.colSpan || 1, 10);
                const text = cell.innerText;
                const link = cell.querySelector("a");

                // Ensure grid row exists for rowspan
                for (let i = 0; i < rowspan; i++) {
                    if (!grid[rowIdx + i]) {
                        grid[rowIdx + i] = [];
                        for (let j = 0; j < 200; j++) { // Initialize new row with columns
                            grid[rowIdx + i][j] = { occupied: false, value: null, link: null };
                        }
                    }
                }

                // Store cell data
                grid[rowIdx][colIdx].value = text;
                grid[rowIdx][colIdx].link = link;

                // Add merge info if rowspan or colspan > 1
                if (rowspan > 1 || colspan > 1) {
                    merges.push({
                        s: { r: rowIdx, c: colIdx },
                        e: { r: rowIdx + rowspan - 1, c: colIdx + colspan - 1 }
                    });
                }

                // Mark occupied cells in the grid
                for (let i = 0; i < rowspan; i++) {
                    for (let j = 0; j < colspan; j++) {
                        if (grid[rowIdx + i] && grid[rowIdx + i][colIdx + j]) {
                            grid[rowIdx + i][colIdx + j].occupied = true;
                        }
                    }
                }
                colIdx += colspan;
            }
            maxC = Math.max(maxC, colIdx); // Update maxC after processing each row
            rowIdx++;
        }

        // Convert grid data to AoA format for SheetJS
        for (let i = 0; i < R; i++) {
            data[i] = [];
            for (let j = 0; j < maxC; j++) { // Iterate up to maxC to ensure all columns are included
                if (grid[i][j] && grid[i][j].value !== null) {
                    data[i][j] = this.buildCell(grid[i][j].value, grid[i][j].link);
                } else {
                    data[i][j] = { v: "" }; // Ensure empty cells are represented
                }
            }
        }

        // Generate worksheet from AoA
        XLSX.utils.sheet_add_aoa(ws, data);

        // Apply merges
        if (merges.length > 0) {
            ws['!merges'] = merges;
        }

        // Set !ref
        ws['!ref'] = XLSX.utils.encode_range({
            s: { r: 0, c: 0 },
            e: { r: R - 1, c: maxC - 1 } // maxC - 1 because maxC is one past the last column index
        });

        return ws;
    }
}
