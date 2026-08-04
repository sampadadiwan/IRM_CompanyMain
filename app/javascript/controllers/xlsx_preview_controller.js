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

    // A fresh connect should never leave a stale guard from a previous render blocking Save.
    this.setSubmitGuard(false);

    const url = this.element.dataset.xlsxPreviewUrl;
    if (url) {
      this.loadFromUrl(url);
    }
  }

  // Disables or re-enables all submit buttons marked with data-xlsx-submit-guard.
  setSubmitGuard(blocked) {
    document.querySelectorAll("[data-xlsx-submit-guard]").forEach((el) => {
      el.disabled = blocked;
    });
  }

  disconnect() {
    document.removeEventListener("upload:complete", this.handleUpload.bind(this));
  }

  capSheetRange(sheet, maxRows = 20000, maxCols = 100) {
    // Some files carry a stale/incorrect dimension tag (e.g. columns were added
    // after the tag was last written) that undercounts the real populated range.
    // SheetJS trusts "!ref" as-is, so relying on it alone can make real trailing
    // columns look "missing". Always compute the actual bounding box from cell
    // addresses and widen (never shrink) whatever "!ref" declares.
    const keys = Object.keys(sheet).filter(k => k[0] !== "!");
    let actualRange = null;
    if (keys.length > 0) {
      let minRow = Infinity, maxRow = -1, minCol = Infinity, maxCol = -1;
      for (const addr of keys) {
        const { r, c } = XLSXLib.utils.decode_cell(addr);
        if (r < minRow) minRow = r;
        if (r > maxRow) maxRow = r;
        if (c < minCol) minCol = c;
        if (c > maxCol) maxCol = c;
      }
      actualRange = { s: { r: minRow, c: minCol }, e: { r: maxRow, c: maxCol } };
      console.log(`🔄 Computed range from cells: ${XLSXLib.utils.encode_range(actualRange)}`);
    }

    let range;
    if (sheet["!ref"]) {
      console.log(`📄 Original !ref from file: ${sheet["!ref"]}`);
      range = XLSXLib.utils.decode_range(sheet["!ref"]);
      if (actualRange) {
        range.s.r = Math.min(range.s.r, actualRange.s.r);
        range.s.c = Math.min(range.s.c, actualRange.s.c);
        range.e.r = Math.max(range.e.r, actualRange.e.r);
        range.e.c = Math.max(range.e.c, actualRange.e.c);
      }
    } else if (actualRange) {
      console.log("⚠️ No !ref found, using range computed from actual cell addresses...");
      range = actualRange;
    } else {
      console.log("❌ Sheet has no cells, skipping");
      return;
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
    // Use `raw: false` to get the formatted text for each cell, as it appears in Excel.
    // This avoids manual date conversion and ensures numbers and dates are displayed correctly.
    const rawData = XLSXLib.utils.sheet_to_json(sheet, { header: 1, blankrows: false, defval: "", raw: false });
    if (!rawData || rawData.length === 0) {
      return [];
    }

    const headers = rawData[0] || [];
    let rows = [];
    if (rawData.length > 1) {
      rows = rawData.slice(1);
    }

    let maxCols = headers.length;
    for (const row of rows) {
      if (row.length > maxCols) {
        maxCols = row.length;
      }
    }

    // Normalize headers to maxCols
    const normalizedHeaders = [...headers];
    while (normalizedHeaders.length < maxCols) {
      normalizedHeaders.push("");
    }

    // Normalize rows to maxCols
    const normalizedRows = rows.map(row => {
      const newRow = [...row];
      while (newRow.length < maxCols) {
        newRow.push("");
      }
      return newRow;
    });

    // Remove completely blank columns
    const nonEmptyColumnIndices = [];
    for (let col = 0; col < maxCols; col++) {
      const headerHasContent = normalizedHeaders[col]?.toString().trim() !== "";
      const anyRowHasContent = normalizedRows.some(row => row[col]?.toString().trim() !== "");
      if (headerHasContent || anyRowHasContent) {
        nonEmptyColumnIndices.push(col);
      }
    }

    const cleanedHeaders = nonEmptyColumnIndices.map(i => normalizedHeaders[i]);
    const cleanedRows = normalizedRows.map(row => nonEmptyColumnIndices.map(i => row[i]));

    return [cleanedHeaders, ...cleanedRows];
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

    console.log("📚 [DEBUG] renderWorkbookTabsOrSingle called");
    console.log("✅ useTabs:", useTabs, "📄 sheetNames:", sheetNames);
    console.log("💾 element.dataset:", this.element.dataset);

    // Most import jobs read sheet 0 server-side (Roo::Spreadsheet#sheet(0)), so
    // header/STANDARD_COLUMNS validation must run against sheet 0 regardless of
    // how many sheets the workbook has or whether they're rendered as tabs.
    // The KPI import is the exception — KpiWorkbookReader scans every sheet — and
    // opts out with data-xlsx-preview-all-sheets so no sheet is named as "the"
    // import sheet.
    const scansAllSheets = this.element.dataset.xlsxPreviewAllSheets === "true";
    const firstSheet = workbook.Sheets[sheetNames[0]];
    if (firstSheet) this.capSheetRange(firstSheet);
    const missingOriginal = firstSheet ? this.checkHeaders(firstSheet, expectedHeaders) : [];

    if (useTabs && sheetNames.length > 1) {
      console.log("🧩 [DEBUG] Multiple sheets detected, building tabs...");
      let tabs = `<nav class="nav nav-pills nav-justified mb-3 align-items-center flex-row" role="tablist">`;
      let tabContents = `<div class="tab-content">`;
      sheetNames.forEach((sheetName, index) => {
        console.log(`➡️ [DEBUG] Processing sheet ${index + 1}/${sheetNames.length}:`, sheetName);
        const sheet = workbook.Sheets[sheetName];
        if (!sheet) {
          console.warn(`⚠️ [DEBUG] Sheet '${sheetName}' not found in workbook!`);
          return;
        }
        this.capSheetRange(sheet);
        const isActive = index === 0 ? "active" : "";
        const tabId = `sheet-${index}`;
        tabs += `<li class="nav-item" role="presentation">
                   <a class="nav-link ${isActive}" id="${tabId}-tab" data-bs-toggle="pill" data-bs-target="#${tabId}" role="tab">${sheetName}</a>
                 </li>`;
        tabContents += `<div class="tab-pane fade show ${isActive}" id="${tabId}" role="tabpanel">
                          <div>${this.buildTableHtml(sheet)}</div>
                        </div>`;
      });
      tabs += `</nav>`;
      tabContents += `</div>`;

      console.log("✅ [DEBUG] Tab HTML generated, injecting into DOM...");

      this.tableTarget.innerHTML = `${tabs}${tabContents}`;
      this.cardTarget.classList.remove("d-none");

      // Only overwrite the "loaded N sheets" success message if header validation
      // didn't already report missing columns above.
      if (statusEl && !missingOriginal.length) {
        const summary = scansAllSheets
          ? `Loaded all ${sheetNames.length} sheets with tabs.`
          : `Loaded all ${sheetNames.length} sheets with tabs. All required columns exist on "${sheetNames[0]}" (used for import).`;
        statusEl.innerHTML = `<div class="alert alert-success">${summary}</div>`;
      }
      console.log("✅ [DEBUG] Multi-tab rendering complete.");
    } else {
      console.log("ℹ️ [DEBUG] Single sheet mode or useTabs disabled.");
      if (!firstSheet) {
        console.error("❌ [DEBUG] No sheet available to render!");
        return;
      }
      console.log(`📊 [DEBUG] Single sheet '${sheetNames[0]}' ready for rendering.`);
      this.renderTable(firstSheet);
    }
  }

  // Compares the sheet's header row against expectedHeaders (STANDARD_COLUMNS),
  // updates the status banner and the submit guard, and returns the list of
  // missing header names (in their original casing).
  checkHeaders(sheet, expectedHeaders) {
    const data = this.normalizeSheetData(sheet);
    const [headers] = data;
    const actual = (headers || [])
      .map((h) => h?.toString().replace("*", "").trim().toLowerCase());
    const required = expectedHeaders.map((h) => h.trim().toLowerCase());

    const statusEl = this.statusElement;
    if (required.length === 0) {
      this.setSubmitGuard(false);
      return [];
    }

    const missingOriginal = expectedHeaders.filter(
      (h) => !actual.includes(h.trim().toLowerCase())
    );
    if (statusEl) {
      statusEl.innerHTML = missingOriginal.length
        ? `<div class="alert alert-danger">Missing required columns: ${missingOriginal.join(", ")}</div>`
        : `<div class="alert alert-success">All required columns exist</div>`;
    }
    this.setSubmitGuard(missingOriginal.length > 0);
    return missingOriginal;
  }

  renderTable(sheet) {
    // ✅ Update only the table within the card body and show card
    const tableHtml = this.buildTableHtml(sheet);
    this.tableTarget.innerHTML = tableHtml;

    // Make sure the card element (defined in HTML) shows
    this.cardTarget.classList.remove("d-none");
  }

  buildTableHtml(sheet) {
    // Safely escape HTML to prevent broken markup
    const escapeHtml = (unsafe) => {
      if (unsafe === null || unsafe === undefined) return "";
      return String(unsafe)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
    };

    // Format cell value: negative numbers rendered in red with parentheses
    const formatCell = (value) => {
      if (value === null || value === undefined || value === "") return "";
      const str = String(value).trim();
      // Match values already in parenthesis format from Excel e.g. (1,850) or (1,241)
      const parenMatch = str.match(/^\(([$€£₹]?[\s]?[\d,]+\.?\d*)(%?)\)$/);
      if (parenMatch) {
        const pct = parenMatch[2];
        return `<span class="text-danger">(${escapeHtml(parenMatch[1])})${pct}</span>`;
      }
      // Match negative numbers/percentages e.g. -1,234.56 or -$1,234 or -21%
      const negativeMatch = str.match(/^-[\s]*([$€£₹]?[\s]?[\d,]+\.?\d*)(%?)$/);
      if (negativeMatch) {
        const absVal = escapeHtml(negativeMatch[1]);
        const pct = negativeMatch[2];
        return `<span class="text-danger">(${absVal})${pct}</span>`;
      }
      return escapeHtml(str);
    };

    const data = XLSXLib.utils.sheet_to_json(sheet, { header: 1, blankrows: false, defval: "", raw: false });
    if (!data || data.length === 0) {
      return '<table class="table table-bordered table-striped dataTable"></table>';
    }

    // Detect tag rows: row begins with "tags"
    const isTagRow = (row) => {
      console.log("Checking for tag row:", row);
      const firstCell = String(row[0] ?? "").trim().toLowerCase();
      return firstCell === "tags";
    };

    // method replicated from kpi_helper
    const tagBadgeClass = (tag) => {
      const value = String(tag ?? "").trim().toLowerCase();
      if (value === "actual") return "bg-primary-subtle text-primary badge-tag-actual";
      if (value === "projected") return "bg-info-subtle text-info badge-tag-projected";
      if (/^ic /.test(value)) return "bg-warning-subtle text-warning badge-tag-ic-case";
      if (/^audited/.test(value)) return "bg-danger-subtle text-danger badge-tag-audited";
      if (value === "budget") return "bg-success-subtle text-success badge-tag-budget";
      return "bg-secondary-subtle text-secondary badge-tag-other";
    };

    const renderTagCell = (value) => {
      const text = String(value ?? "").trim();
      if (text === "") return "";
      return text.split(/[;,]\s*/).filter(Boolean).map((tag) => {
        return `<small class="badge badge-pill ${tagBadgeClass(tag)}">${escapeHtml(tag)}</small>`;
      }).join(" ");
    };

    const renderHeaderTags = (index) => {
      const badgeHtml = tagRows
        .map(row => String(row[index] ?? "").trim())
        .filter(value => value !== "" && value.toLowerCase() !== "tags")
        .map(renderTagCell)
        .filter(Boolean)
        .join(" ");

      return badgeHtml ? `<span class="d-block">${badgeHtml}</span>` : "";
    };

    let headerRows = [data[0] || []];
    let tagRows = [];
    let dataStartIndex = 1;

    while (dataStartIndex < data.length && isTagRow(data[dataStartIndex])) {
      tagRows.push(data[dataStartIndex]);
      dataStartIndex += 1;
    }

    console.log(headerRows.length, "header row(s) detected:", headerRows);
    console.log(tagRows.length, "tag row(s) detected:", tagRows);
    const rows = data.slice(dataStartIndex);
    const maxCols = Math.max(...headerRows.map(r => r.length), ...tagRows.map(r => r.length), ...rows.map(r => r.length), 0);

    let html = '<table class="table table-bordered table-striped dataTable table-grey">';
    html += '<thead>';
    headerRows.forEach(headerRow => {
      html += '<tr>';
      for (let i = 0; i < maxCols; i++) {
        const thClass = i === 0 ? ' class="align-middle"' : ' class="text-center"';
        html += `<th${thClass}>${escapeHtml(headerRow[i] || "")}${renderHeaderTags(i)}</th>`;
      }
      html += '</tr>';
    });
    html += '</thead><tbody>';


    rows.forEach(row => {
      html += '<tr>';
      for (let i = 0; i < maxCols; i++) {
        html += `<td>${formatCell(row[i])}</td>`;
      }
      html += '</tr>';
    });

    html += '</tbody></table>';
    return html;
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
      let useTabs = this.element.dataset.xlsxPreviewTabs === "true";
      const sheetNames = workbook.SheetNames;

      // 🧩 Auto-enable tabbed view for multiple sheets
      if (sheetNames.length > 1 && !useTabs) {
        console.warn("⚙️ [DEBUG] Auto-enabling tabbed view: Multiple sheets detected but xlsxPreviewTabs was false.");
        useTabs = true;
      }

      console.log("📚 [DEBUG] loadFromUrl called with workbook:", workbook);
      console.log("✅ [DEBUG] useTabs:", useTabs, "📄 sheetNames:", sheetNames);
      console.log("💾 [DEBUG] element.dataset:", this.element.dataset);

      if (!sheetNames || sheetNames.length === 0) {
        console.error("❌ [DEBUG] No sheets found in workbook!");
        if (statusEl) {
          statusEl.innerHTML = `<div class="alert alert-danger">No sheets found in file!</div>`;
        }
        return;
      }

      const filenameEl = this.filenameElement;
      if (filenameEl) {
        filenameEl.textContent = url.split("/").pop();
      }

      if (useTabs && sheetNames.length > 1) {
        console.log("🧩 [DEBUG] Multiple sheets detected, building tabs...");
        let tabs = `<nav class="nav nav-pills nav-justified p-3 mb-3 rounded align-items-center card flex-row" role="tablist">`;
        let tabContents = `<div class="tab-content">`;

        sheetNames.forEach((sheetName, index) => {
          console.log(`➡️ [DEBUG] Processing sheet ${index + 1}/${sheetNames.length}:`, sheetName);
          const sheet = workbook.Sheets[sheetName];
          if (!sheet) {
            console.warn(`⚠️ [DEBUG] Sheet '${sheetName}' not found!`);
            return;
          }
          this.capSheetRange(sheet);
          const isActive = index === 0 ? "active" : "";
          const tabId = `sheet-${index}`;

          tabs += `<a class="nav-link ${isActive}" data-bs-toggle="pill" href="#${tabId}">${sheetName}</a>`;

          tabContents += `<div id="${tabId}" class="tab-pane fade ${isActive} show">
                            <div>${this.buildTableHtml(sheet)}</div>
                          </div>`;
        });

        tabs += `</nav>`;
        tabContents += `</div>`;

        console.log("✅ [DEBUG] Fund-like style tabs constructed successfully.");
        this.tableTarget.innerHTML = `${tabs}${tabContents}`;

        if (statusEl) {
          statusEl.innerHTML = `<div class="alert alert-success">Loaded all ${sheetNames.length} sheets as tabs</div>`;
        }
        console.log("✅ [DEBUG] Tab rendering completed successfully.");

        // ✅ Ensure cardTarget is visible when multiple tabs rendered
        if (this.cardTarget) {
          this.cardTarget.classList.remove("d-none");
        } else {
          console.warn("⚠️ [DEBUG] cardTarget missing. Tabs may not display correctly.");
        }
      } else {
        console.log("ℹ️ [DEBUG] Single sheet mode triggered or useTabs disabled.");
        const sheet = workbook.Sheets[sheetNames[0]];
        if (!sheet) {
          console.error("❌ [DEBUG] Workbook missing first sheet content.");
          if (statusEl) {
            statusEl.innerHTML = `<div class="alert alert-danger">Workbook has no readable sheets.</div>`;
          }
          return;
        }

        this.capSheetRange(sheet);
        console.log(`📊 [DEBUG] Single sheet parsed, preparing to render.`);

        try {
          this.renderTable(sheet);
          if (this.cardTarget) this.cardTarget.classList.remove("d-none");
        } catch (renderErr) {
          console.error("❌ [DEBUG] Error while rendering table:", renderErr);
          if (statusEl) {
            statusEl.innerHTML = `<div class="alert alert-danger">Error rendering table: ${renderErr.message}</div>`;
          }
        }
      }

      const message = useTabs && sheetNames.length > 1
        ? `Loaded all ${sheetNames.length} sheets as tabs`
        : `Loaded ${sheetNames[0]}`;
      if (statusEl) {
        statusEl.innerHTML = `<div class="alert alert-success">${message}</div>`;
      }

      console.log("🏁 [DEBUG] Workbook render process complete.");

    } catch (error) {
      const statusEl = this.statusElement;
      if (statusEl) {
        statusEl.innerHTML = `<div class="alert alert-danger">${error.message}</div>`;
      }
    }

    console.log(`Loading completed and rendered XLSX from URL: ${url}`);
  }
}
