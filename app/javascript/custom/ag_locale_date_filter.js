import { appDateFormat, dateFormatHint, formatLocaleDate, parseDate, parseLocaleDate } from "custom/locale_date_format"

// Custom `dateComponent` for ag-Grid's agDateColumnFilter.
//
// ag-Grid's stock date filter renders a bare <input type="date">, which can only be
// driven by the browser's segmented entry or its calendar popup — there is no way to
// type a date, and the segments follow the BROWSER's locale rather than the app's. That
// is the same class of silent mismatch that the moment `en`-only build caused in the
// grid cells: the column displays dd/mm/yyyy and the filter above it expects mm/dd/yyyy.
//
// This replaces it with the same widget shape the Rails forms use — a text input you
// type into, in the app's locale format, plus a calendar icon for the native picker —
// so a date reads and is entered identically in a cell, a form and a filter.
//
// Implements the v30 IDateComp contract: getDate/setDate are mandatory,
// afterGuiAttached/setInputPlaceholder/setInputAriaLabel optional.
export class LocaleDateFilterComponent {
  init(params) {
    this.params = params;
    this.format = appDateFormat();
    this.date = null;

    // ag-Grid appends this into its own filter body — don't re-declare one here.
    this.eGui = document.createElement("div");
    this.eGui.className = "ag-locale-date-filter";
    this.eGui.innerHTML = `
      <div class="ag-input-field ag-text-field" role="presentation">
        <div class="ag-input-field-wrapper ag-wrapper" role="presentation">
          <input class="ag-input-field-input ag-text-field-input" type="text" autocomplete="off">
          <span class="ag-locale-date-filter-icon" role="button" tabindex="-1">
            <i class="fas fa-calendar"></i>
          </span>
          <input class="ag-locale-date-filter-picker" type="date" tabindex="-1" aria-hidden="true">
        </div>
      </div>`;

    this.eInput = this.eGui.querySelector(".ag-input-field-input");
    this.eIcon = this.eGui.querySelector(".ag-locale-date-filter-icon");
    this.ePicker = this.eGui.querySelector(".ag-locale-date-filter-picker");

    const hint = dateFormatHint(this.format);
    if (hint) {
      this.eInput.placeholder = hint;
      this.eInput.title = `Enter date as ${hint}`;
    }

    this.eInput.addEventListener("input", () => this.onTyped());
    this.eInput.addEventListener("blur", () => this.onBlur());
    // Enter must not reach the grid's own key handling, which closes the popup
    // before the filter has taken the freshly typed value.
    this.eInput.addEventListener("keydown", (e) => {
      if (e.key === "Enter") e.stopPropagation();
    });
    this.eIcon.addEventListener("click", () => this.openPicker());
    this.ePicker.addEventListener("change", () => this.onPicked());
  }

  getGui() {
    return this.eGui;
  }

  // ag-Grid hands the comparator a date at local midnight, so return one to match.
  getDate() {
    return this.date;
  }

  setDate(date) {
    this.date = toLocalMidnight(date);
    this.eInput.value = this.date ? formatLocaleDate(this.date, this.format) : "";
    this.ePicker.value = this.date ? isoOf(this.date) : "";
    this.eInput.classList.remove("ag-locale-date-filter-invalid");
  }

  setInputPlaceholder(placeholder) {
    // Only take ag-Grid's placeholder when we have no format hint of our own —
    // "dd/mm/yyyy" tells the user more than ag-Grid's generic label does.
    if (!this.eInput.placeholder) this.eInput.placeholder = placeholder;
  }

  setInputAriaLabel(label) {
    this.eInput.setAttribute("aria-label", label);
  }

  afterGuiAttached(params) {
    if (params && params.suppressFocus) return;
    this.eInput.focus();
  }

  setDisabled(disabled) {
    this.eInput.disabled = !!disabled;
    this.ePicker.disabled = !!disabled;
  }

  openPicker() {
    try {
      this.ePicker.showPicker();
    } catch (_e) {
      // showPicker() needs a user gesture — the click handler always provides one
    }
  }

  onTyped() {
    // A partially typed date is not a filter value yet. Clearing on the way through
    // matters: leaving the previous date applied would keep filtering on a bound the
    // user has already edited away from.
    this.applyDate(parseIsoToLocalDate(parseLocaleDate(this.eInput.value, this.format)));
    if (this.date) this.eInput.classList.remove("ag-locale-date-filter-invalid");
  }

  onBlur() {
    const raw = this.eInput.value.trim();
    if (!raw) {
      this.eInput.classList.remove("ag-locale-date-filter-invalid");
      return;
    }
    const iso = parseLocaleDate(raw, this.format);
    if (iso) {
      // Normalise what the user typed ("1.2.2026") to the locale format
      this.eInput.value = formatLocaleDate(iso, this.format);
      this.eInput.classList.remove("ag-locale-date-filter-invalid");
    } else {
      this.eInput.classList.add("ag-locale-date-filter-invalid");
    }
  }

  onPicked() {
    const date = parseIsoToLocalDate(this.ePicker.value || null);
    if (!date) return;
    this.eInput.value = formatLocaleDate(date, this.format);
    this.eInput.classList.remove("ag-locale-date-filter-invalid");
    this.applyDate(date);
  }

  // Commits a date and tells ag-Grid to re-run the filter, but only on an actual
  // change — onDateChanged triggers a full filter pass, and typing fires per keystroke.
  applyDate(date) {
    const next = toLocalMidnight(date);
    if (sameDay(next, this.date)) return;
    this.date = next;
    this.ePicker.value = next ? isoOf(next) : "";
    this.params.onDateChanged();
  }
}

// The date filter is configured in TWO places, and putting either half in the other
// one fails silently:
//
//   localeDateGridOptions -> the GRID options object. ag-Grid resolves the date
//     component with getCompDetails(this.gridOptions, {propertyName: "dateComponent"},
//     "agDateInput", ...) — it reads gridOptions and nothing else. A `dateComponent`
//     placed in a column's filterParams is ignored without warning and you get the
//     stock calendar-only <input type="date"> back.
//
//   localeDateFilterParams -> the COLUMN's filterParams, for the comparator, which is
//     per-column and has no meaning at grid level.
//
// Every grid that builds its own gridOptions has to spread the first one in;
// BaseAgGrid, the deals list and the adhoc grid each construct their own.
export const localeDateGridOptions = {
  dateComponent: LocaleDateFilterComponent
};

export const localeDateFilterParams = {
  comparator: (filterLocalDateAtMidnight, cellValue) => {
    // cellValue is the raw value in the cell. ag-Grid hands us the filter date at
    // local midnight, so compare at day granularity — otherwise a timestamped cell
    // never tests "equals" the picked day.
    if (!cellValue) return -1;
    const cellDate = parseDate(cellValue);
    if (!cellDate) return -1;
    cellDate.setHours(0, 0, 0, 0);
    const diff = cellDate.getTime() - filterLocalDateAtMidnight.getTime();
    if (diff < 0) return -1;
    if (diff > 0) return 1;
    return 0;
  }
};

function toLocalMidnight(date) {
  if (!date) return null;
  const d = new Date(date.getTime());
  if (isNaN(d.getTime())) return null;
  d.setHours(0, 0, 0, 0);
  return d;
}

// ISO "YYYY-MM-DD" -> Date at LOCAL midnight. `new Date(iso)` would read it as UTC
// and land on the previous day for any negative-offset browser.
function parseIsoToLocalDate(iso) {
  if (!iso) return null;
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(y, m - 1, d);
}

function isoOf(date) {
  const pad = (n) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function sameDay(a, b) {
  if (!a && !b) return true;
  if (!a || !b) return false;
  return a.getTime() === b.getTime();
}
