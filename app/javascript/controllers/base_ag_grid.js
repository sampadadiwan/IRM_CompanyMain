import { Controller } from "@hotwired/stimulus"
import { formatLocaleDate } from 'custom/locale_date_format';
import { localeDateFilterParams } from 'custom/ag_locale_date_filter';

export default class BaseAgGrid extends Controller {

    static gridOptions = {};
    static grid;

    static values = {
        lazyLoadData: String, // Do we want to eager or lazy load (for tabs)
        tableName: String, // Which table id are we targeting
        customFields: String // Custom fields to be added to the grid
    }

    disconnect() {
        if (this._beforeCacheHandler) document.removeEventListener('turbo:before-cache', this._beforeCacheHandler)
    }



    connect() {
        let source = $(this.tableNameValue).data('source')
        console.log(`source = ${source}`);
        console.log(`tableNameValue = ${this.tableNameValue}`);
        console.log(`lazyLoadDataValue = ${this.lazyLoadDataValue}`);
        console.log(`customFieldsValue = ${this.customFieldsValue}`);

        if (this.lazyLoadDataValue == "false") {
            this.init(this.tableNameValue);
        }
    }

    snakeToHuman(str) {
        return str
          .split('_') // Split the string by underscores
          .map(word => word.charAt(0).toUpperCase() + word.slice(1)) // Capitalize first letter
          .join(' '); // Join the words with spaces
    }


    init(tableName) {
        let restoreColumnState = this.restoreColumnState;
        let saveColumnState = this.saveColumnState;

        this.decimalPlaces = this.extractDecimalPlaces();

        // let the grid know which columns and what data to use
        this.gridOptions = {
            getRowId: params => params.data.id,
            defaultExcelExportParams: {
                columnKeys: this.getExportColumns(),
            },
            columnDefs: this.columnDefs(),
            rowHeight: 60,
            suppressAggFuncInHeader: true,
            defaultColDef: {
                // flex: 1,
                resizable: true,
                filter: 'agTextColumnFilter',
                sortable: true,
                minWidth: 120,
            },
            onGridReady: (event) => {
                this.gridOptions.api = event.api;
                this.gridOptions.columnApi = event.columnApi;
                this.configureFixedLayoutFixes();
                this.restoreColumnVisibilityState(this.gridOptions, this.tableNameValue);
                this.gridReady();
                this.refreshGridLayout(event);
            },
            onFirstDataRendered: (event) => {
                this.ensureFirstRowVisible(event);
            },

            onColumnVisible: (event) => {
                this.saveColumnVisibilityState(this.gridOptions, this.tableNameValue);
            },

            autoGroupColumnDef: {
                minWidth: 200,
                cellRendererParams: {
                    footerValueGetter: params =>  {
                        const isRootLevel = params.node.level === -1;
                        if (isRootLevel) {
                            return 'Total';
                        }
                        return `Sub Total (${params.value})`;
                    },
                }
            },


            enableRangeSelection: true,
            enableCharts: true,
            rowGroupPanelShow: 'always',
            suppressDragLeaveHidesColumns: true,
            suppressMakeColumnVisibleAfterUnGroup: true,
            suppressRowGroupHidesColumns: true,
            pagination: true,
            paginationPageSizeSelector: [25, 50, 100],
            paginationPageSize: 25,

             // adds subtotals
            groupIncludeFooter: this.includeFooter(),
            // includes grand total
            groupIncludeTotalFooter: this.includeTotalFooter(),

            statusBar: {
                statusPanels: [
                    { statusPanel: 'agTotalAndFilteredRowCountComponent', align: 'left' },
                    { statusPanel: 'agTotalRowCountComponent', align: 'center' },
                    { statusPanel: 'agFilteredRowCountComponent' },
                    { statusPanel: 'agSelectedRowCountComponent' },
                    { statusPanel: 'agAggregationComponent' },
                ]
            },
            sideBar: {
                toolPanels: [
                    {
                        id: 'columns',
                        labelDefault: 'Columns',
                        labelKey: 'columns',
                        iconKey: 'columns',
                        toolPanel: 'agColumnsToolPanel',
                        toolPanelParams: {
                            // suppressValues: true,
                            // suppressPivots: true,
                            // suppressPivotMode: true,
                            // suppressRowGroups: false
                        }
                    },
                    {
                        id: 'filters',
                        labelDefault: 'Filters',
                        labelKey: 'filters',
                        iconKey: 'filter',
                        toolPanel: 'agFiltersToolPanel',
                    }
                ],
                defaultToolPanel: ''
            }

        };

        // setup the grid after the page has finished loading
        let gridDiv = document.querySelector(tableName);
        this.gridElement = gridDiv;
        this.grid = new agGrid.Grid(gridDiv, this.gridOptions);

        this.loadData();

        // We need to destroy the grid when we leave the page, but skip
        // destruction for hash-only navigations (Turbo snapshots the page
        // for hash changes but no re-render will follow). This mirrors the
        // Select2 fix which keeps instances alive for hash-only navigation.
        var api = this.gridOptions.api;

        this._beforeCacheHandler = function () {
            try {
                const current = new URL(location.href);
                const cached = new URL(document.location.href);
                const isHashOnly = current.pathname === cached.pathname && current.search === cached.search;
                if (isHashOnly) return;
            } catch (err) {
                // If URL parsing fails, fall back to destroying to be safe
            }

            try {
                if (api && api.destroy) api.destroy();
            } catch (e) {
                console.warn('AG Grid destroy failed during before-cache', e);
            }
        };

        document.addEventListener('turbo:before-cache', this._beforeCacheHandler);

    }

    saveColumnVisibilityState(gridOptions, columnStateKey) {
        if (gridOptions.columnApi) {
            console.log('Saving column visibility state');

            // Get the column state
            const columnState = gridOptions.columnApi.getColumnState();

            // Filter the state to only include visibility (hide) property
            const filteredColumnState = columnState.map(col => ({
                colId: col.colId,   // The column ID
                hide: col.hide      // Column visibility (true if hidden)
            }));

            // Save the filtered state to localStorage
            localStorage.setItem(columnStateKey, JSON.stringify(filteredColumnState));
            console.log('Column visibility state saved:', filteredColumnState);
        }
    }

    restoreColumnVisibilityState(gridOptions, columnStateKey) {
        const savedColumnState = JSON.parse(localStorage.getItem(columnStateKey));

        console.log('Restoring column visibility state:', savedColumnState);

        if (savedColumnState && gridOptions.columnApi) {
            const isStateValid = gridOptions.columnApi.applyColumnState({
                state: savedColumnState,
                applyOrder: false // Only apply visibility, not the column order
            });

            if (!isStateValid) {
                console.warn('Failed to restore column visibility state. The columns may have changed.');
            }
        }
    }

    // read obj["a.b.c"] safely
    getByPath(obj, path) {
        return path.split('.').reduce((o, k) => (o ? o[k] : undefined), obj);
    }

    // write obj["a.b.c"] = val
    setByPath(obj, path, val) {
        const keys = path.split('.');
        const last = keys.pop();
        const target = keys.reduce((o, k) => {
            if (!o[k]) o[k] = {};
            return o[k];
        }, obj);
        target[last] = val;
    }

    loadData() {
        let source = $(this.tableNameValue).data('source')
        let restoreColumnState = this.restoreColumnState;
        console.log(`loadData from ${source}`);
        fetch(source)
            .then(response => response.json())
            .then(data => {
                // load fetched data into grid
                console.log(`loadData completed from ${source}`);
                /* ② ---------- CLEAN JUST ONCE ---------- */
                // This is to ensure fields sent back as strings are converted to numbers so we can display them correctly
                if (Array.isArray(this.numericColumns) && this.numericColumns.length) {
                    const cleanNumber = (v) =>
                    v == null || v === "" ? null : Number(String(v).replace(/,/g, ""));

                    data.forEach(row => {
                        this.numericColumns.forEach(col => {
                            // Only touch it if it’s not already a number
                            const raw = this.getByPath(row, col);
                            if (typeof raw === "string") {
                                this.setByPath(row, col, cleanNumber(raw));
                            }
                        });
                    });
                }
                console.log(data);
                this.gridOptions.api.setRowData(data);
                // this.restoreColumnState(this.gridOptions);
            });
    }

    ensureFirstRowVisible(event) {
        const api = event?.api || this.gridOptions?.api;
        if (!api) return;

        if (api.getDisplayedRowCount() <= 0) return;

        // Guard against stale scroll position from cached views.
        requestAnimationFrame(() => {
            try {
                const gridElement = this.getGridElement();
                const bodyViewport = gridElement?.querySelector('.ag-body-viewport');
                this.applyFixedHeaderOffset(gridElement);
                if (bodyViewport) bodyViewport.scrollTop = 0;
                api.ensureIndexVisible(0, 'top');
            } catch (e) {
                console.warn('Unable to reset AG Grid initial scroll position', e);
            }
        });
    }

    refreshGridLayout(event) {
        const api = event?.api || this.gridOptions?.api;
        if (!api) return;

        // Turbo/lazy containers can report transient sizes during initial paint.
        // Run layout once on next frame and once shortly after to stabilize scroll.
        requestAnimationFrame(() => {
            try {
                if (api.doLayout) api.doLayout();
                this.applyFixedHeaderOffset(this.getGridElement());
                this.ensureFirstRowVisible({ api });
            } catch (e) {
                console.warn('Unable to refresh AG Grid layout on initial render', e);
            }
        });

        setTimeout(() => {
            try {
                if (api.doLayout) api.doLayout();
                this.applyFixedHeaderOffset(this.getGridElement());
            } catch (_e) {
                // No-op; this is a best-effort follow-up pass.
            }
        }, 80);
    }

    getGridElement() {
        if (this.gridElement) return this.gridElement;
        this.gridElement = document.querySelector(this.tableNameValue);
        return this.gridElement;
    }

    hasInlineFixedHeight(gridElement) {
        if (!gridElement) return false;
        const height = (gridElement.style.height || '').trim();
        const minHeight = (gridElement.style.minHeight || '').trim();

        const isFixedValue = (value) => {
            if (!value) return false;
            const normalized = value.toLowerCase();
            if (normalized === 'auto' || normalized === '0' || normalized === '0px') return false;
            return /\d/.test(normalized);
        };

        return isFixedValue(height) || isFixedValue(minHeight);
    }

    shouldEnableFixedLayoutFixes(gridElement) {
        if (!gridElement) return false;

        const fixedLayoutFlag = (gridElement.dataset.agFixedLayout || '').toLowerCase();
        const legacyFlag = (gridElement.dataset.fixedHeaderOffset || '').toLowerCase();
        if (fixedLayoutFlag === 'true' || fixedLayoutFlag === '1') return true;
        if (legacyFlag === 'true' || legacyFlag === '1') return true;

        // Auto-enable for grids explicitly rendered with fixed inline heights.
        return this.hasInlineFixedHeight(gridElement);
    }

    configureFixedLayoutFixes() {
        const gridElement = this.getGridElement();
        if (!gridElement) return;

        if (this.shouldEnableFixedLayoutFixes(gridElement)) {
            gridElement.classList.add('ag-fixed-layout-managed');
        } else {
            gridElement.classList.remove('ag-fixed-layout-managed');
            const bodyViewport = gridElement.querySelector('.ag-body-viewport');
            if (bodyViewport) {
                bodyViewport.style.position = '';
                bodyViewport.style.top = '';
                bodyViewport.style.height = '';
            }
        }
    }

    applyFixedHeaderOffset(gridElement) {
        if (!gridElement) return;

        // Apply offset fix only to deals_list_grid and capital_commitments_table
        if (!gridElement.classList.contains('ag-fixed-layout-managed')) return;

        const bodyViewport = gridElement.querySelector('.ag-body-viewport');
        if (!bodyViewport) return;

        // Only apply offset fix to capital commitments grid. deals_list_grid is
        // excluded: its header is a normal flex item, so the viewport already
        // starts below it and the offset just pushed a header-height of blank
        // space above the first row.
        const gridId = gridElement.id;
        if (gridId !== 'capital_commitments_table') {
            return;
        }

        const header = gridElement.querySelector('.ag-header');
        if (!header) return;

        const headerHeight = header.offsetHeight || 0;
        if (headerHeight <= 0) return;

        // Apply offset to viewport to move it past the header
        bodyViewport.style.position = 'relative';
        bodyViewport.style.top = `${headerHeight}px`;
        bodyViewport.style.height = `calc(100% - ${headerHeight}px)`;
    }

    setWidthAndHeight(size) {
        var eGridDiv = document.querySelector('#capital_commitments');
        eGridDiv.style.setProperty('width', size);
        eGridDiv.style.setProperty('height', size);
    }

    html(params) {
        return params.value ? params.value : '';
    }

    html_column(controller, field, headerName, enableRowGroup = true, enablePivot = true) {
        return {
            field: field, headerName: headerName, enableRowGroup: enableRowGroup, enablePivot: enablePivot,
            cellRenderer: function (params) {
              return controller.renderCell(params, field, field);
            },
            valueGetter: (params) => {
              if (params.data !== undefined) {
                return params.data[field]
              }
            }
          }

    }
    // Helper function to format numbers with commas and specified decimal places
    // The previous implementation was not working correctly with custom decimal places passed
    formatNumberWithCommas(value, decimals = 2) {
        const precision = Number.isFinite(decimals) ? decimals : 2;
        const rounded = Number(value).toFixed(precision);
        const [integerPart, fractionalPart] = rounded.split('.');
        const withCommas = integerPart.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
        return fractionalPart !== undefined ? `${withCommas}.${fractionalPart}` : withCommas;
    }


    numberFormatColumn(controller, field, headerName, formatNumberWithCommas, aggFunc = "sum", enableRowGroup = true, enablePivot = true) {
        return {
            field: field,
            headerName: headerName,
            filter: "agNumberColumnFilter",
            enableRowGroup: enableRowGroup,
            enablePivot: enablePivot,
            chartDataType: 'series',
            aggFunc: aggFunc,
            type: 'numericColumn',
            cellClass: 'right-align-cell',
            valueFormatter: function (params) {
              if (params.value != null) {
                // Format the number with two decimal places and comma separators
                                return formatNumberWithCommas(params.value);
              } else {
                return params.value;
              }
            }
          };
    }
        // Extract decimal place value from the data source URL
        extractDecimalPlaces() {
                const source = $(this.tableNameValue).data('source');
                if (!source) { return null; }

                try {
                        const url = new URL(source, window.location.origin);
                        const decimalsParam = url.searchParams.get('decimals');
                        return decimalsParam ? parseInt(decimalsParam, 10) : null;
                } catch (error) {
                        console.warn('Unable to parse decimals from source url', error);
                        return null;
                }
        }

    /**
     * Creates a date column definition for ag-Grid.
     *
     * @param {Object} controller  - Typically `this` (the controller instance).
     * @param {string} field       - The data field in your JSON row data.
     * @param {string} headerName  - The human-readable column header.
     * @param {string} dateFormat  - Optional strftime pattern (e.g. '%b %d, %Y').
     *                               When omitted the active Rails locale's date
     *                               format is used. NOT a moment/dayjs pattern —
     *                               the app speaks strftime everywhere.
     * @param {boolean} enableRowGroup - Enable row grouping on this column.
     * @param {boolean} enablePivot - Enable pivot on this column.
     * @param {boolean} rowGroup   - Whether or not this column itself is part of the row group.
     * @return {Object} The column definition object for ag-Grid.
     */
    dateFormatColumn(
        controller,
        field,
        headerName,
        dateFormat = null,
        enableRowGroup = true,
        enablePivot = true,
        rowGroup = false
      ) {
        return {
          field: field,
          headerName: headerName,
          filter: 'agDateColumnFilter',   // enable date-specific filter
          enableRowGroup: enableRowGroup,
          enablePivot: enablePivot,
          rowGroup: rowGroup,
          chartDataType: 'category',
          // Typeable locale-format filter input + the day-granularity comparator.
          filterParams: localeDateFilterParams,
          valueFormatter: (params) => {
            // Guard falsy values before parsing: ag-Grid passes '' for an empty
            // cell, and a date column has no meaningful epoch-0 reading.
            if (!params.value) return '';
            // With no explicit `dateFormat` this falls back to the active Rails
            // locale's date format (the app-date-format meta tag), so the cell
            // matches every server-rendered date on the page.
            return formatLocaleDate(params.value, dateFormat);
          }
        };
      }


    textColumn(controller, field, headerName, aggFunc, enableRowGroup = true, enablePivot = true, rowGroup = false) {
        return {
            field: field,
            headerName: headerName,
            filter: "agSetColumnFilter",
            enableRowGroup: enableRowGroup,
            rowGroup: rowGroup,
            enablePivot: enablePivot,
            chartDataType: 'category',
            aggFunc: aggFunc}
    }

    getExportColumns() {
        let colsDefs = this.columnDefs();
        // console.log(colsDefs);
        // We dont want the dt_actions column in the export
        let fields = colsDefs.filter(function (col) { return col.field != "dt_actions" }).map(function (col) { return col.field });
        // console.log(`exportToXL = ${fields}`);
        return fields;
    }

    exportToXL() {


        this.gridOptions.api.exportDataAsExcel({
            processCellCallback(params) {
                const value = params.value;
                console.log(params);
                function extract_text_from_html(html_text) {
                    console.log(html_text);
                    if (typeof html_text === 'string' || html_text instanceof String) {
                        let ret_val = html_text.replace(/<\/?[^>]+(>|$)/g, "");
                        return ret_val
                    } else {
                        return html_text;
                    }
                }

                return value === undefined ? '' : extract_text_from_html(value) //`_${value}_`
            }
        });
    }

    onFilterTextBoxChanged() {
        this.gridOptions.api.setQuickFilter(
            document.getElementById('filter-text-box').value
        );
    }

    extract_number(str_num) {
        let ret_val = Number(str_num.replace(/[^0-9.-]+/g, ""));
        return ret_val;
    }

    extract_text_from_html(html_text) {
        let ret_val = html_text.replace(/<\/?[^>]+(>|$)/g, "");
        return ret_val
    }

    format_currency(number, currency) {
        // console.log(`format_currency(${number}, ${currency})`);
        return new Intl.NumberFormat('en-IN', { style: 'currency', currency: currency }).format(number);
    }

    renderCell(params, field_key, field_name=null) {
        if (params.data !== undefined) {
            return params.data[field_key];
        } else if (field_name !== null && params.node.field === field_name || params.node.field === field_key) {
            return params.node.key;
        }
    }


    includeFooter() {
        return true;
    }

    includeTotalFooter() {
        return true;
    }

    resetAllFilters() {
        this.gridOptions.api.setFilterModel(null);
    }

    gridReady(params) {
    }

}
