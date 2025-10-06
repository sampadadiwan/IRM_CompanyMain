import { Controller } from "@hotwired/stimulus";
import * as XLSX from "xlsx";
const XLSXLib = XLSX && XLSX.read ? XLSX : window.XLSX;

export default class extends Controller {
  static targets = ["card", "table"];

  get filenameElement() {
    return this.element.querySelector('[data-xlsx-preview-target="filename"]');
  }

  get statusElement() {
    return this.element.querySelector('[data-xlsx-preview-target="status"]');
  }

  connect() {
    document.addEventListener("upload:complete", this.handleUpload.bind(this));

    const url = this.element.dataset.xlsxPreviewUrl;
    if (url) {
      this.loadFromUrl(url);
    }
  }

  disconnect() {
    document.removeEventListener("upload:complete", this.handleUpload.bind(this));
  }

  capSheetRange(sheet, maxRows = 20000, maxCols = 100) {
    let range;

    if (sheet["!ref"]) {
      console.log(`📄 Original !ref from file: ${sheet["!ref"]}`);
      range = XLSXLib.utils.decode_range(sheet["!ref"]);
    } else {
      console.log("⚠️ No !ref found, computing from actual cell addresses...");
      const keys = Object.keys(sheet).filter(k => k[0] !== "!");
      if (keys.length === 0) {
        console.log("❌ Sheet has no cells, skipping");
        return;
      }

      let minRow = Infinity, maxRow = -1, minCol = Infinity, maxCol = -1;
      for (const addr of keys) {
        const { r, c } = XLSXLib.utils.decode_cell(addr);
        if (r < minRow) minRow = r;
        if (r > maxRow) maxRow = r;
        if (c < minCol) minCol = c;
        if (c > maxCol) maxCol = c;
      }
      range = { s: { r: minRow, c: minCol }, e: { r: maxRow, c: maxCol } };
      console.log(`🔄 Computed range from cells: ${XLSXLib.utils.encode_range(range)}`);
    }

    const rowCount = range.e.r - range.s.r + 1;
    const colCount = range.e.c - range.s.c + 1;
    console.log(`➡️ Detected range size: ${rowCount} rows × ${colCount} cols`);

    // ✅ Cap rows
    if (rowCount > maxRows) {
      range.e.r = range.s.r + maxRows - 1;
      console.log(`✂️ Row cap applied: now ${maxRows} rows`);
    }

    // ✅ Cap columns
    if (colCount > maxCols) {
      range.e.c = range.s.c + maxCols - 1;
      console.log(`✂️ Column cap applied: now ${maxCols} cols`);
    }

    sheet["!ref"] = XLSXLib.utils.encode_range(range);
    console.log(`✅ Final capped !ref: ${sheet["!ref"]}`);
  }




  handleUpload(event) {

    console.log(`Received upload:complete event`);

    const { file } = event.detail;
    const expectedHeaders =
      JSON.parse(this.element.dataset.headers || "[]") || [];

    console.log(`Expected headers: ${expectedHeaders.join(", ")}`);

    const filenameEl = this.filenameElement;
    if (filenameEl) {
      filenameEl.textContent = `${file.name}`;
    }
    const statusEl = this.statusElement;
    if (statusEl) {
      statusEl.innerHTML = `<div class="alert alert-info">Processing ${file.name}...</div>`;
    }

    console.log(`Reading file: ${file.name}`);

    const reader = new FileReader();
    reader.onload = (e) => {
      console.log(`File read successfully: ${file.name}`);
      const data = new Uint8Array(e.target.result);
      const workbook = XLSXLib.read(data, { type: "array" });
      const sheet = workbook.Sheets[workbook.SheetNames[0]];

      // ✅ Cap to 10k rows
      this.capSheetRange(sheet);


      // === Trim !ref before parsing ===
      if (sheet["!ref"]) {
        const range = XLSXLib.utils.decode_range(sheet["!ref"]);
        while (range.e.r > range.s.r) {
          let hasData = false;
          for (let c = range.s.c; c <= range.e.c; c++) {
            const cell = sheet[XLSXLib.utils.encode_cell({ r: range.e.r, c })];
            if (cell && cell.v != null && cell.v.toString().trim() !== "") {
              hasData = true;
              break;
            }
          }
          if (hasData) break;
          range.e.r--; // shrink bottom
        }
        sheet["!ref"] = XLSXLib.utils.encode_range(range);
      }

      const jsonData = XLSXLib.utils.sheet_to_json(sheet, { header: 1 });
      console.log(`Parsed ${jsonData.length} rows from sheet: ${workbook.SheetNames[0]}`);
      this.validateAndRender(jsonData, expectedHeaders);
    };


    reader.readAsArrayBuffer(file);
  }

  validateAndRender(data, expectedHeaders) {
    const [headers, ...rows] = data;
    const actual = headers
      .map((h) => h?.toString().replace("*", "").trim().toLowerCase());
    const required = expectedHeaders.map((h) => h.trim().toLowerCase());
    const missing = required.filter((h) => !actual.includes(h));

    if (required.length > 0) {
      const missingOriginal = expectedHeaders.filter(
        (h) => !actual.includes(h.trim().toLowerCase())
      );
      const statusEl = this.statusElement;
      if (statusEl) {
        statusEl.innerHTML = missingOriginal.length
          ? `<div class="alert alert-danger">Missing required columns: ${missingOriginal.join(", ")}</div>`
          : `<div class="alert alert-success">All required columns exist</div>`;
      }
    }

    this.renderTable(headers, rows);
  }

  renderTable(headers, rows) {
    const thead = `<thead><tr>${headers.map((h) => `<th>${h}</th>`).join("")}</tr></thead>`;
    const tbody = `<tbody>${rows
      .map(
        (row) =>
          `<tr>${row.map((cell) => `<td>${cell ?? ""}</td>`).join("")}</tr>`
      )
      .join("")}</tbody>`;
    this.tableTarget.innerHTML = `<table class="table table-bordered datatable jqDataTable">${thead}${tbody}</table>`;
    this.cardTarget.classList.remove("d-none");
  }

  async loadFromUrl(url) {
    console.log(`Loading started and rendered XLSX from URL: ${url}`);



    try {
      const statusEl = this.statusElement;
      if (statusEl) {
        statusEl.innerHTML = `<div class="alert alert-info">Loading from ${url}...</div>`;
      }

      const response = await fetch(url);
      if (!response.ok) throw new Error(`Failed to fetch file: ${response.statusText}`);
      const arrayBuffer = await response.arrayBuffer();
      const data = new Uint8Array(arrayBuffer);

      const workbook = XLSXLib.read(data, { type: "array" });
      const sheet = workbook.Sheets[workbook.SheetNames[0]];

      // ✅ Cap to 10k rows
      this.capSheetRange(sheet);

      const jsonData = XLSXLib.utils.sheet_to_json(sheet, { header: 1, blankrows: false });

      const filenameEl = this.filenameElement;
      if (filenameEl) {
        filenameEl.textContent = url.split("/").pop();
      }
      if (statusEl) {
        statusEl.innerHTML = `<div class="alert alert-success">Loaded ${workbook.SheetNames[0]}</div>`;
      }
      this.renderTable(jsonData[0], jsonData.slice(1));
    } catch (error) {
      const statusEl = this.statusElement;
      if (statusEl) {
        statusEl.innerHTML = `<div class="alert alert-danger">${error.message}</div>`;
      }
    }

    console.log(`Loading completed and rendered XLSX from URL: ${url}`);
  }

}