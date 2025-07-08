import { Controller } from "@hotwired/stimulus"
import moment from 'moment'; // instead of dayjs

export default class BaseAgGrid extends Controller {

    static gridOptions = {};
    static grid;

    static values = {
        lazyLoadData: String, // Do we want to eager or lazy load (for tabs)
        tableName: String, // Which table id are we targeting
        customFields: String // Custom fields to be added to the grid
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
                this.restoreColumnVisibilityState(this.gridOptions, this.tableNameValue);
                this.gridReady();
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
        this.grid = new agGrid.Grid(gridDiv, this.gridOptions);

        this.loadData();

        // We need to destroy the grid when we leave the page
        var api = this.gridOptions.api;
        $(document).on('turbo:before-cache', function () {
            api.destroy();
        });        

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
+               /* ② ------------------------------------ */
                console.log(data);
                this.gridOptions.api.setRowData(data);
                // this.restoreColumnState(this.gridOptions);
            });
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

    formatNumberWithCommas(value) {
        const rounded = Number(value).toFixed(2); // e.g., "1234.57"
        return rounded.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
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

    /**
     * Creates a date column definition for ag-Grid.
     *
     * @param {Object} controller  - Typically `this` (the controller instance).
     * @param {string} field       - The data field in your JSON row data.
     * @param {string} headerName  - The human-readable column header.
     * @param {string} dateFormat  - A dayjs (or moment) format string. Defaults to 'YYYY-MM-DD'.
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
          // Optionally, you can define a custom comparator for date filtering:
          filterParams: {
            comparator: (filterLocalDateAtMidnight, cellValue) => {
              // cellValue is the raw value in the cell.
              if (!cellValue) return -1;  // or 0, depending on your use case
              // parse the date using dayjs or moment
              const cellDate = dayjs(cellValue);
              if (cellDate.isBefore(filterLocalDateAtMidnight)) return -1;
              if (cellDate.isAfter(filterLocalDateAtMidnight)) return 1;
              return 0;
            },
          },
          valueFormatter: (params) => {
            if (!params.value) return '';
            
            // 1. Use the browser's locale
            const userLocale = navigator.language || navigator.userLanguage;

            // 2. Set moment’s locale
            const m = moment(params.value).locale(userLocale);

            // 3. Format the date either using moment’s default locale format
            //    or a fallback if you want something explicit.
            //    - `m.format('L')` uses a standard localized date format.
            //    - `m.format(dateFormat || 'L')` lets you override if you pass a specific format.
            return m.format(dateFormat || 'L');
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