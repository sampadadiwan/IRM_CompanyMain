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
    // Revert to document-level listener but filter inside handleUpload to specific upload ID
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

  normalizeSheetData(sheet) {
    var rawData = XLSXLib.utils.sheet_to_json(sheet, { header: 1, blankrows: false, defval: "" });
    if (!rawData || rawData.length === 0) {
      return [];
    }

    var headers = rawData[0] || [];
    var rows = [];
    if (rawData.length > 1) {
      for (var i = 1; i < rawData.length; i++) {
        rows.push(rawData[i]);
      }
    }

    var maxCols = 0;
    for (var r = 0; r < rawData.length; r++) {
      if (rawData[r] && rawData[r].length > maxCols) {
        maxCols = rawData[r].length;
      }
    }

    var normalizedHeaders = [];
    for (var c = 0; c < maxCols; c++) {
      normalizedHeaders.push(headers[c] ? headers[c] : "");
    }
    headers = normalizedHeaders;

    var normalizedRows = [];
    for (var rr = 0; rr < rows.length; rr++) {
      var row = [];
      for (var cc = 0; cc < maxCols; cc++) {
        row.push(rows[rr][cc] ? rows[rr][cc] : "");
      }
      normalizedRows.push(row);
    }

    // ✅ Remove completely blank columns (no header and all rows empty)
    var nonEmptyColumnIndices = [];
    for (var col = 0; col < headers.length; col++) {
      var headerHasContent = headers[col] && headers[col].toString().trim() !== "";
      var anyRowHasContent = false;
      for (var rowIdx = 0; rowIdx < normalizedRows.length; rowIdx++) {
        var val = normalizedRows[rowIdx][col];
        if (val && val.toString().trim() !== "") {
          anyRowHasContent = true;
          break;
        }
      }
      if (headerHasContent || anyRowHasContent) {
        nonEmptyColumnIndices.push(col);
      }
    }

    var cleanedHeaders = [];
    for (var x = 0; x < nonEmptyColumnIndices.length; x++) {
      cleanedHeaders.push(headers[nonEmptyColumnIndices[x]]);
    }

    var cleanedRows = [];
    for (var y = 0; y < normalizedRows.length; y++) {
      var filteredRow = [];
      for (var z = 0; z < nonEmptyColumnIndices.length; z++) {
        filteredRow.push(normalizedRows[y][nonEmptyColumnIndices[z]]);
      }
      cleanedRows.push(filteredRow);
    }

    var result = [];
    result.push(cleanedHeaders);
    for (var rr2 = 0; rr2 < cleanedRows.length; rr2++) {
      result.push(cleanedRows[rr2]);
    }

    return result;
    // remove trailing invalid TS/ESNext block
    var headers = rawData[0] || [];
    var rows = [];
    for (var ri = 1; ri < rawData.length; ri++) {
      rows.push(rawData[ri]);
    }

    var maxCols = 0;
    for (var i = 0; i < rawData.length; i++) {
      if (rawData[i].length > maxCols) {
        maxCols = rawData[i].length;
      }
    }

    var normalizedHeaders = [];
    for (var ci = 0; ci < maxCols; ci++) {
      normalizedHeaders.push(headers[ci] ? headers[ci] : "");
    }
    headers = normalizedHeaders;

    var output = [];
    output.push(headers);
    for (var j = 0; j < rows.length; j++) {
      output.push(rows[j]);
    }
    return output;
  }




  handleUpload(event) {
    const file = event.detail.file;
    const uploadId = event.detail.uploadId;
    const controllerUploadId = this.element.dataset.uploadId;

    // If controller has a specific upload-id, only react to that one.
    // Logic: allow if uploadId or event.target.closest('[id]') matches.
    if (controllerUploadId) {
      const targetId = event.target?.id || event.target?.closest('[id]')?.id;
      if (uploadId !== controllerUploadId && targetId !== controllerUploadId) {
        console.log('Ignoring upload:complete for different uploadId or target: ' + (uploadId || targetId));
        return;
      }
    }

    console.log('Received upload:complete event for uploadId:', uploadId);

    // file was already extracted from event.detail earlier
    const expectedHeaders = JSON.parse(this.element.dataset.headers || "[]") || [];

    console.log(`Expected headers: ${expectedHeaders.join(", ")}`);

    const filenameEl = this.filenameElement;
    if (filenameEl) filenameEl.textContent = `${file.name}`;

    const statusEl = this.statusElement;
    if (statusEl)
      statusEl.innerHTML = `<div class="alert alert-info">Processing ${file.name}...</div>`;

    console.log(`Reading file: ${file.name}`);

    const reader = new FileReader();
    reader.onload = (e) => {
      console.log(`File read successfully: ${file.name}`);
      const data = new Uint8Array(e.target.result);
      const workbook = XLSXLib.read(data, { type: "array" });

      // Use a central tab rendering method
      this.renderWorkbookTabsOrSingle(workbook, expectedHeaders);
    };

    reader.readAsArrayBuffer(file);
  }

  renderWorkbookTabsOrSingle(workbook, expectedHeaders = []) {
    const useTabs = this.element.dataset.xlsxPreviewTabs === "true";
    const sheetNames = workbook.SheetNames;
    const statusEl = this.statusElement;

    if (useTabs && sheetNames.length > 1) {
      let tabs = `<nav class="nav nav-pills nav-justified mb-3 rounded align-items-center flex-row" role="tablist">`;
      let tabContents = `<div class="tab-content">`;
      sheetNames.forEach((sheetName, index) => {
        const sheet = workbook.Sheets[sheetName];
        this.capSheetRange(sheet);
        const jsonData = this.normalizeSheetData(sheet);
        const isActive = index === 0 ? "active" : "";
        const tabId = `sheet-${index}`;
        tabs += `<li class="nav-item" role="presentation">
                   <button class="nav-link ${isActive}" id="${tabId}-tab" data-bs-toggle="tab" data-bs-target="#${tabId}" type="button" role="tab">${sheetName}</button>
                 </li>`;
        tabContents += `<div class="tab-pane fade show ${isActive}" id="${tabId}" role="tabpanel">
                          <div>${this.buildTableHtml(jsonData[0], jsonData.slice(1))}</div>
                        </div>`;
      });
      tabs += `</nav>`;
      tabContents += `</div>`;

      // ✅ Wrap tabs & tables inside Bootstrap card
      const cardHtml = `
        <div class="card mt-3">
          <div class="card-header fw-bold">
            <span class="h3" data-xlsx-preview-target="filename">${this.filenameElement?.textContent || "XLSX Preview"}</span>
          </div>
          <div class="card-body">
            <div data-xlsx-preview-target="status"></div>
            <div class="table-responsive">
              ${tabs}
              ${tabContents}
            </div>
          </div>
        </div>`;

      // ✅ Populate targets directly, not replace them
      this.tableTarget.innerHTML = `${tabs}${tabContents}`;
      this.cardTarget.classList.remove("d-none");

      if (statusEl)
        statusEl.innerHTML = `<div class="alert alert-success">Loaded all ${sheetNames.length} sheets with tabs</div>`;
    } else {
      const sheet = workbook.Sheets[sheetNames[0]];
      this.capSheetRange(sheet);
      const jsonData = this.normalizeSheetData(sheet);
      this.validateAndRender(jsonData, expectedHeaders, workbook);
    }
  }

  validateAndRender(data, expectedHeaders, workbook = null) {
    const [headers, ...rows] = data;
    const actual = headers
      .map((h) => h?.toString().replace("*", "").trim().toLowerCase());
    const required = expectedHeaders.map((h) => h.trim().toLowerCase());
    const missing = required.filter((h) => !actual.includes(h));

    const statusEl = this.statusElement;
    if (required.length > 0) {
      const missingOriginal = expectedHeaders.filter(
        (h) => !actual.includes(h.trim().toLowerCase())
      );
      if (statusEl) {
        statusEl.innerHTML = missingOriginal.length
          ? `<div class="alert alert-danger">Missing required columns: ${missingOriginal.join(", ")}</div>`
          : `<div class="alert alert-success">All required columns exist</div>`;
      }
    }

    // Support multi-sheet rendering here too
    const useTabs = this.element.dataset.xlsxPreviewTabs === "true";
    if (workbook && useTabs && workbook.SheetNames.length > 1) {
      let tabs = `<nav class="nav nav-pills nav-justified p-3 mb-3 rounded align-items-center card flex-row" role="tablist">`;
      let tabContents = `<div class="tab-content">`;
      workbook.SheetNames.forEach((sheetName, index) => {
        const sheet = workbook.Sheets[sheetName];
        this.capSheetRange(sheet);
        const jsonData = this.normalizeSheetData(sheet);
        const isActive = index === 0 ? "active" : "";
        const tabId = `validate-sheet-${index}`;
        tabs += `<li class="nav-item" role="presentation">
                   <button class="nav-link ${isActive}" id="${tabId}-tab" data-bs-toggle="tab" data-bs-target="#${tabId}" type="button" role="tab">${sheetName}</button>
                 </li>`;
        tabContents += `<div class="tab-pane fade show ${isActive}" id="${tabId}" role="tabpanel">
                          <div>${this.buildTableHtml(jsonData[0], jsonData.slice(1))}</div>
                        </div>`;
      });
      tabs += `</nav>`;
      tabContents += `</div>`;
      this.tableTarget.innerHTML = `${tabs}${tabContents}`;
      this.cardTarget.classList.remove("d-none");
      if (statusEl)
        statusEl.innerHTML = `<div class="alert alert-success">Loaded all ${workbook.SheetNames.length} sheets with tabs</div>`;
    } else {
      this.renderTable(headers, rows);
    }
  }

  renderTable(headers, rows) {
    const thead = `<thead><tr>${headers.map((h) => `<th>${h}</th>`).join("")}</tr></thead>`;
    const tbody = `<tbody>${rows
      .map(
        (row) =>
          `<tr>${row.map((cell) => `<td>${cell ?? ""}</td>`).join("")}</tr>`
      )
      .join("")}</tbody>`;

    // ✅ Update only the table within the card body and show card
    const tableHtml = `<table class="table table-bordered datatable jqDataTable">${thead}${tbody}</table>`;
    this.tableTarget.innerHTML = tableHtml;

    // Make sure the card element (defined in HTML) shows
    this.cardTarget.classList.remove("d-none");
  }

  buildTableHtml(headers, rows) {
    const thead = `<thead><tr>${headers.map((h) => `<th>${h}</th>`).join("")}</tr></thead>`;
    const tbody = `<tbody>${rows
      .map(
        (row) =>
          `<tr>${row.map((cell) => `<td>${cell ?? ""}</td>`).join("")}</tr>`
      )
      .join("")}</tbody>`;
    return `<table class="table table-bordered datatable jqDataTable">${thead}${tbody}</table>`;
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
      const useTabs = this.element.dataset.xlsxPreviewTabs === "true";
      const sheetNames = workbook.SheetNames;

      const filenameEl = this.filenameElement;
      if (filenameEl) {
        filenameEl.textContent = url.split("/").pop();
      }

      if (useTabs && sheetNames.length > 1) {
        let tabs = `<ul class="nav nav-tabs" role="tablist">`;
        let tabContents = `<div class="tab-content">`;
        sheetNames.forEach((sheetName, index) => {
          const sheet = workbook.Sheets[sheetName];
          this.capSheetRange(sheet);
          const jsonData = this.normalizeSheetData(sheet);
          const isActive = index === 0 ? "active" : "";
          const tabId = `sheet-${index}`;
          tabs += `<li class="nav-item" role="presentation">
                     <button class="nav-link ${isActive}" id="${tabId}-tab" data-bs-toggle="tab" data-bs-target="#${tabId}" type="button" role="tab">${sheetName}</button>
                   </li>`;
          tabContents += `<div class="tab-pane fade show ${isActive}" id="${tabId}" role="tabpanel">
                            <div>${this.buildTableHtml(jsonData[0], jsonData.slice(1))}</div>
                          </div>`;
        });
        tabs += `</ul>`;
        tabContents += `</div>`;
        this.tableTarget.innerHTML = `${tabs}${tabContents}`;
      } else {
        const sheet = workbook.Sheets[sheetNames[0]];
        this.capSheetRange(sheet);
        const jsonData = this.normalizeSheetData(sheet);
        this.renderTable(jsonData[0], jsonData.slice(1));
      }

      const message = useTabs && sheetNames.length > 1
        ? `Loaded all ${sheetNames.length} sheets as tabs`
        : `Loaded ${sheetNames[0]}`;
      if (statusEl) {
        statusEl.innerHTML = `<div class="alert alert-success">${message}</div>`;
      }

    } catch (error) {
      const statusEl = this.statusElement;
      if (statusEl) {
        statusEl.innerHTML = `<div class="alert alert-danger">${error.message}</div>`;
      }
    }

    console.log(`Loading completed and rendered XLSX from URL: ${url}`);
  }

  buildTableHtml(headers, rows) {
    const thead = `<thead><tr>${headers.map((h) => `<th>${h}</th>`).join("")}</tr></thead>`;
    const tbody = `<tbody>${rows
      .map(
        (row) =>
          `<tr>${row.map((cell) => `<td>${cell ?? ""}</td>`).join("")}</tr>`
      )
      .join("")}</tbody>`;
    return `<table class="table table-bordered datatable jqDataTable">${thead}${tbody}</table>`;
  }

}