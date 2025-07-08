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
        const ws = XLSX.utils.aoa_to_sheet([]);
        let R = 0, maxC = 0;

        for (const row of tableElement.rows) {
            let C = 0;
            for (const cell of row.cells) {
            const text = cell.innerText;
            const link = cell.querySelector("a");
            ws[XLSX.utils.encode_cell({ r: R, c: C })] = this.buildCell(text, link);
            C++;
            }
            maxC = Math.max(maxC, C);
            R++;
        }

        ws["!ref"] = XLSX.utils.encode_range({
            s: { r: 0, c: 0 },
            e: { r: R - 1, c: maxC - 1 }
        });

        const wb = XLSX.utils.book_new();
        XLSX.utils.book_append_sheet(wb, ws, "Sheet1");
        XLSX.writeFile(wb, filename);
    }

}
