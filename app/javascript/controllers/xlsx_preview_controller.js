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

  handleUpload(event) {
    const { file } = event.detail;
    const expectedHeaders =
      JSON.parse(this.element.dataset.headers || "[]") || [];

    const filenameEl = this.filenameElement;
    if (filenameEl) {
      filenameEl.textContent = `${file.name}`;
    }
    const statusEl = this.statusElement;
    if (statusEl) {
      statusEl.innerHTML = `<div class="alert alert-info">Processing ${file.name}...</div>`;
    }

    const reader = new FileReader();
    reader.onload = (e) => {
      const data = new Uint8Array(e.target.result);
      const workbook = XLSXLib.read(data, { type: "array" });
      const sheet = workbook.Sheets[workbook.SheetNames[0]];
      const jsonData = XLSXLib.utils.sheet_to_json(sheet, { header: 1 });
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
      const jsonData = XLSXLib.utils.sheet_to_json(sheet, { header: 1 });
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
  }
}