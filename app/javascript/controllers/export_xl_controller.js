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
        var wb = XLSX.utils.table_to_book(elt, { sheet: "sheet1" });
        return dl ?
            XLSX.write(wb, { bookType: type, bookSST: true, type: 'base64' }) :
            XLSX.writeFile(wb, fn || (`${filename}.` + (type || 'xlsx')));
    }

}
