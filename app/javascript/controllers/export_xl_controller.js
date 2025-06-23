import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

    connect() {
        console.log("Export XL");
    }

    export(event) {
        
        console.log("export called");

        let table_id = event.target.dataset.tableid 
        let filename = event.target.dataset.filename 
        let table = document.getElementById(table_id);

        filename = filename ? filename + '.xlsx' : 'export.xlsx';

        this.exportToExcel('xlsx', table_id, filename);
    }

    exportToExcel(type, table_id, filename, fn, dl) {
        var elt = document.getElementById(table_id);
        var ws = XLSX.utils.aoa_to_sheet([]); // Create an empty worksheet

        // Iterate through table rows and cells to extract data and hyperlinks
        var R = 0; // Row counter
        var maxC = 0; // Maximum column counter across all rows

        for (let i = 0; i < elt.rows.length; i++) {
            let row = elt.rows[i];
            let C = 0; // Column counter for current row
            for (let j = 0; j < row.cells.length; j++) {
                let cell = row.cells[j];
                let cell_text = cell.innerText;
                let cell_link = cell.querySelector('a');
                let cell_obj = { v: cell_text };

                if (cell_link && cell_link.href) {
                    cell_obj.l = { Target: cell_link.href };
                }
                
                // Determine cell address and add to worksheet
                let cell_address = XLSX.utils.encode_cell({ r: R, c: C });
                ws[cell_address] = cell_obj;
                C++;
            }
            if (C > maxC) { // Update maxC if current row has more columns
                maxC = C;
            }
            R++;
        }

        // Set worksheet dimensions using maxC for the widest row
        ws['!ref'] = XLSX.utils.encode_range({ s: { r: 0, c: 0 }, e: { r: R - 1, c: maxC - 1 } });

        var wb = XLSX.utils.book_new();
        XLSX.utils.book_append_sheet(wb, ws, "sheet1");

        return dl ?
            XLSX.write(wb, { bookType: type, bookSST: true, type: 'base64' }) :
            XLSX.writeFile(wb, fn || (`${filename}.` + (type || 'xlsx')));
    }

}
