import { Controller } from "@hotwired/stimulus"

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
                flex: 1,
                resizable: true,
                filter: 'agTextColumnFilter',
                sortable: true,
                minWidth: 120,
            },
            onGridReady: (event) => {
                this.gridOptions.api = event.api;
                this.gridOptions.columnApi = event.columnApi;
                this.restoreColumnVisibilityState(this.gridOptions, this.tableNameValue);
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

    loadData() {
        let source = $(this.tableNameValue).data('source')
        console.log(`loadData from ${source}`);
        fetch(source)
            .then(response => response.json())
            .then(data => {
                // load fetched data into grid
                console.log(`loadData completed from ${source}`);
                console.log(data);
                this.gridOptions.api.setRowData(data);
                this.restoreColumnState(this.gridOptions);
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
        return value.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
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

    textColumn(controller, field, headerName, aggFunc, enableRowGroup = true, enablePivot = true) {
        return { 
            field: field,
            headerName: headerName, 
            filter: "agSetColumnFilter", 
            enableRowGroup: enableRowGroup, 
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
    
}