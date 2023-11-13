import { Controller } from "@hotwired/stimulus"

export default class BaseAgGrid extends Controller {

    static gridOptions = {};
    static grid;

    static values = {
        lazyLoadData: String, // Do we want to eager or lazy load (for tabs)
        tableName: String // Which table id are we targeting
    }

    connect() {
        console.log(`connect AgGrid: ${this.tableNameValue}`);
        console.log(`Datatable setup for ${this.tableNameValue}`);
        let source = $(this.tableNameValue).data('source')
        console.log(`source = ${source}`);
        console.log(`lazyLoadDataValue = ${this.lazyLoadDataValue}`);

        if (this.lazyLoadDataValue == "false") {
            this.init(this.tableNameValue);
        }
    }


    init(tableName) {

        // let the grid know which columns and what data to use
        this.gridOptions = {
          columnDefs: this.columnDefs(),
          rowHeight: 60,
          defaultColDef: {
            flex: 1,
            resizable: true,
            filter: 'agTextColumnFilter',
            sortable: true,
            minWidth: 120,
          },
          enableRangeSelection: true,
          enableCharts: true,
          rowGroupPanelShow: 'always',
          suppressDragLeaveHidesColumns: true,
          suppressMakeColumnVisibleAfterUnGroup: true,
          suppressRowGroupHidesColumns: true,
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
        $(document).on('turbo:before-cache', function() {    
          api.destroy();      
        });
    
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
        return new Intl.NumberFormat('en-US', { style: 'currency', currency: currency }).format(number);
    }
}