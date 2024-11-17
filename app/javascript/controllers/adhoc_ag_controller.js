import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    console.log("AdhocAg javascript loaded");
    this.loadData();
  }

  loadData() {
    // Initialize grid
    const dynamicGrid = new DynamicAgGrid('adhoc_grid');
    dynamicGrid.init();

    const gridElement = document.getElementById('adhoc_grid');
    const gridData = JSON.parse(gridElement.dataset.gridData || '[]');
    dynamicGrid.updateGrid(gridData);

    // Example data fetch and update
    // fetch('account_entries.json?fund_id=&q%5Bc%5D%5B0%5D%5Ba%5D%5B0%5D%5Bname%5D=&q%5Bc%5D%5B0%5D%5Bp%5D=eq&q%5Bc%5D%5B0%5D%5Bv%5D%5B0%5D%5Bvalue%5D=&template=adhoc&agg_type=sum&agg_field=amount&group_fields%5B%5D=entry_type&group_fields%5B%5D=fund_name')
    //     .then(response => response.json())
    //     .then(data => {
    //         dynamicGrid.updateGrid(data);
    //     })
    //     .catch(error => console.error('Error fetching data:', error));
  }

}



// Create grid class to handle dynamic grid creation and updates
class DynamicAgGrid {
    constructor(containerId) {
        this.gridContainer = document.getElementById(containerId);
        this.gridOptions = {
            defaultColDef: {
                sortable: true,
                filter: true,
                resizable: true,
                minWidth: 100,
                enableRowGroup: true,  // Enable row grouping
                enablePivot: true,      // Enable pivoting    
                flex: 1
            },
            suppressColumnVirtualisation: true,
            allowDragFromColumnsToolPanel: true,

            rowHeight: 60,
            enableRangeSelection: true,
            enableCharts: true,
            rowGroupPanelShow: 'always',
            suppressDragLeaveHidesColumns: true,
            suppressMakeColumnVisibleAfterUnGroup: true,
            suppressRowGroupHidesColumns: true,
            pagination: true,
            paginationPageSizeSelector: [25, 50, 100],
            paginationPageSize: 25,
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
        this.grid = null;
    }

    // Initialize the grid
    init() {
        // Initialize the grid
        this.grid = new agGrid.Grid(this.gridContainer, this.gridOptions);
    }

    // Infer column type from data
    inferColumnType(value) {
        if (typeof value === 'number') return 'numericColumn';
        if (value instanceof Date) return 'dateColumn';
        if (typeof value === 'boolean') return 'booleanColumn';
        return 'textColumn';
    }

    // Helper function to humanize column headers
    humanizeHeader(str) {
        // Handle snake_case, camelCase, and kebab-case
        return str
            // Convert snake_case and kebab-case to spaces
            .replace(/[-_]+/g, ' ')
            // Convert camelCase to spaces
            .replace(/([a-z])([A-Z])/g, '$1 $2')
            // Capitalize first letter of each word
            .split(' ')
            .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
            .join(' ');
    }

    // Format number with commas and 2 decimal places
    formatNumber(number) {
        return new Intl.NumberFormat('en-US', {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        }).format(number);
    }

    // Generate column definitions from data
    generateColumnDefs(data) {
        if (!data || data.length === 0) return [];

        // Take first row as sample to generate columns
        const sampleRow = data[0];
        
        return Object.keys(sampleRow).map(key => {
            const value = sampleRow[key];
            const columnType = this.inferColumnType(value);
            console.log(`key = ${key}, value = ${value}, columnType = ${columnType}`);
            
            const colDef = {
                field: key,
                headerName: this.humanizeHeader(key),
                sortable: true,
                filter: true,
                resizable: true,
            };

            // Add specific configurations based on column type
            switch (columnType) {
                case 'numericColumn':
                    colDef.type = 'numericColumn';
                    colDef.filter = 'agNumberColumnFilter';
                    colDef.aggFunc = 'sum';
                    colDef.cellClass = 'right-align-cell';
                    // Add number formatting
                    colDef.valueFormatter = (params) => {
                        if (params.value === null || params.value === undefined) return '';
                        return this.formatNumber(params.value);
                    };
                    // Ensure proper filtering and sorting of formatted numbers
                    colDef.filterValueGetter = (params) => {
                        if (params.value === null || params.value === undefined) return null;
                        return parseFloat(params.value);
                    };
                    colDef.comparator = (valueA, valueB) => {
                        return valueA - valueB;
                    };
                    break;
                case 'dateColumn':
                    colDef.type = 'dateColumn';
                    colDef.filter = 'agDateColumnFilter';
                    colDef.valueFormatter = (params) => {
                        return params.value ? new Date(params.value).toLocaleDateString() : '';
                    };
                    break;
                case 'booleanColumn':
                    colDef.cellRenderer = 'agBooleanCellRenderer';
                    colDef.aggFunc = 'count';
                    break;
                default:
                    colDef.filter = 'agTextColumnFilter';
                    colDef.aggFunc = 'count';
            }

            return colDef;
        });
    }

    // Update grid with new data
    updateGrid(data) {
        if (!data || data.length === 0) {
            console.warn('No data provided to update grid');
            return;
        }

        const columnDefs = this.generateColumnDefs(data);
        
        // In newer versions of ag-Grid, we update through gridOptions
        this.gridOptions.api.setColumnDefs(columnDefs);
        this.gridOptions.api.setRowData(data);
    }

    // Method to handle column state
    saveColumnState() {
        return this.gridOptions.columnApi.getColumnState();
    }

    // Method to restore column state
    restoreColumnState(columnState) {
        if (columnState) {
            this.gridOptions.columnApi.applyColumnState({ state: columnState });
        }
    }
}

// Usage example:
/*
// HTML:
<div id="adhoc_grid"></div>

// JavaScript:
// Initialize grid
const dynamicGrid = new DynamicAgGrid('adhoc_grid');
dynamicGrid.init();

// Example data fetch and update
fetch('your-api-endpoint')
    .then(response => response.json())
    .then(data => {
        dynamicGrid.updateGrid(data);
    })
    .catch(error => console.error('Error fetching data:', error));

// Save column state example
const savedState = dynamicGrid.saveColumnState();
localStorage.setItem('gridState', JSON.stringify(savedState));

// Restore column state example
const savedState = JSON.parse(localStorage.getItem('gridState'));
dynamicGrid.restoreColumnState(savedState);
*/