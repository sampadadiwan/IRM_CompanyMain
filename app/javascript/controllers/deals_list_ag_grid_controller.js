import BaseAgGrid from "controllers/base_ag_grid"
import moment from 'moment'

export default class extends BaseAgGrid {
  static values = {
    dealId: Number,
    investorLabel: String,
    currency: String,
    activityTemplates: Array,
    customFields: String
  }

  columnDefs() {
    const columns = [
      {
        field: 'investor_name',
        headerName: this.investorLabelValue,
        checkboxSelection: true,
        headerCheckboxSelection: true,
        pinned: 'left',
        lockPinned: true,
        width: 350,
        autoHeight: true,
        wrapText: true,
        cellRenderer: (params) => {
          if (params.data) {
            const logoUrl = params.data.investor_logo_url;
            const initials = params.data.investor_initials || '??';
            const tags = params.data.tags || '';
            const notes = params.data.notes || '';

            const avatarHtml = logoUrl
              ? `<img src="${logoUrl}" class="rounded-circle" alt="user" width="50" height="50">`
              : `<div class="rounded-circle bg-light d-flex align-items-center justify-content-center text-muted fw-bold" style="width: 50px; height: 50px;">${initials}</div>`;

            const tagsHtml = tags.split(',').map(tag => tag.trim()).filter(tag => tag !== '').map(tag => {
              const url = new URL(window.location.href);
              url.searchParams.set('q[tags_cont]', tag);
              return `<a href="${url.toString()}" class="badge rounded-pill bg-info-subtle text-primary border-info-subtle me-1 mb-1" style="font-weight: 500; text-decoration: none; font-size: 0.75rem !important; padding: 0.2rem 0.5rem !important;">${tag}</a>`;
            }).join('');

            const tooltipAttr = notes ? `data-bs-toggle="tooltip" data-bs-html="true" title="${notes.replace(/"/g, '"')}"` : '';

            return `
              <div class="d-flex flex-row comment-row p-2 gap-3" style="white-space: normal !important; line-height: 1.2;">
                <div class="flex-shrink-0">
                  <span>${avatarHtml}</span>
                </div>
                <div class="comment-text w-100">
                  <div class="d-flex align-items-center mb-1">
                    <h6 class="fw-medium mb-0 me-2">
                      <a href="#" data-action="click->deals-list-ag-grid#openSidepanel" data-id="${params.data.id}" class="text-dark" ${tooltipAttr}>${params.value}</a>
                    </h6>
                  </div>

                  <div class="mb-1">
                    ${tagsHtml}
                  </div>

                  <div class="comment-footer mt-1">
                    <div class="d-flex align-items-center">
                    </div>
                  </div>
                </div>
              </div>
            `;
          }
        }
      },
      {
        field: 'health_score',
        headerName: 'Health',
        width: 100,
        cellRenderer: (params) => {
          if (params.value === undefined || params.value === null) return '';
          const score = parseFloat(params.value);
          let color = '#ef4444'; // Red
          if (score > 70) color = '#00b090'; // Green
          else if (score > 30) color = '#ffa000'; // Amber

          return `
            <div style="width: 100%; height: 100%; display: flex; align-items: center; gap: 8px;">
              <div style="flex-grow: 1; height: 10px; background: #eee; border-radius: 5px; overflow: hidden; position: relative; min-width: 50px;">
                <div style="width: ${score}%; height: 100%; background-color: ${color} !important; border-radius: 5px;"></div>
              </div>
              <span style="font-size: 0.85rem; font-weight: 700; min-width: 40px; color: ${color};">${score}%</span>
            </div>
          `;
        }
      },
      {
        field: 'status',
        headerName: 'Status',
        filter: 'agSetColumnFilter',
        enableRowGroup: true,
        editable: true,
        cellEditor: 'agSelectCellEditor',
        cellEditorParams: {
          values: ['New', 'Interested', 'In Progress', 'Committed', 'Complete', 'Declined']
        },
        cellRenderer: (params) => {
          if (!params.value) return '';
          let badgeClass = 'bg-secondary-light';
          if (params.value === 'Active' || params.value === 'Committed' || params.value === 'Complete') badgeClass = 'bg-success-light';
          if (params.value === 'Pending' || params.value === 'Interested' || params.value === 'In Progress') badgeClass = 'bg-warning-light';
          if (params.value === 'Declined') badgeClass = 'bg-danger-light';
          return `<span class="badge ${badgeClass}">${params.value}</span>`;
        }
      },
      {
        field: 'stagnant',
        headerName: 'Stagnant',
        width: 100,
        cellRenderer: (params) => {
          if (params.data && params.data.stagnant) {
            const reason = params.data.stagnant_reason || 'No activity for more than 7 days';
            return `<span class="badge bg-danger-light" data-bs-toggle="tooltip" title="${reason}">Stagnant</span>`;
          }
          return '';
        }
      },
      this.numberFormatColumn(this, 'primary_amount', `Primary (${this.currencyValue})`, this.formatNumberWithCommas, 'sum', true),
      { ...this.numberFormatColumn(this, 'secondary_investment', `Secondary (${this.currencyValue})`, this.formatNumberWithCommas, 'sum', true), editable: true },
      { ...this.numberFormatColumn(this, 'pre_money_valuation', `Pre Money (${this.currencyValue})`, this.formatNumberWithCommas, 'sum', true), editable: true },
      {
        field: 'tier',
        headerName: 'Tier',
        filter: 'agSetColumnFilter',
        enableRowGroup: true,
        editable: true,
        cellRenderer: (params) => {
          if (!params.value) return '';
          let badgeClass = 'bg-info-light';
          if (params.value === 'Tier 1' || params.value === '1') badgeClass = 'bg-primary-light';
          if (params.value === 'Tier 2' || params.value === '2') badgeClass = 'bg-success-light';
          if (params.value === 'Tier 3' || params.value === '3') badgeClass = 'bg-warning-light';
          if (params.value === 'Tier 4' || params.value === '4') badgeClass = 'bg-danger-light';
          return `<span class="badge ${badgeClass}">${params.value}</span>`;
        }
      }
    ];

    if (this.hasActivityTemplatesValue) {
      this.activityTemplatesValue.forEach(template => {
        columns.push({
          field: `activity_${template.id}`,
          headerName: template.title,
          enableRowGroup: true,
          editable: true,
          cellEditor: 'agSelectCellEditor',
          cellEditorParams: {
            values: ['Complete', 'Incomplete', 'Skip']
          },
          cellRenderer: (params) => {
            const getBadge = (status, details = null) => {
              if (status === '-' || status === 'Template' || !status) return '-';

              let badgeClass = 'bg-secondary-light';
              if (status === 'Complete') badgeClass = 'bg-success-light';
              if (status === 'Incomplete') badgeClass = 'bg-danger-light';
              if (status === 'Skip') badgeClass = 'bg-warning-light';

              const tooltipAttr = details ? `data-bs-toggle="tooltip" data-bs-html="true" title="${details.replace(/"/g, '"')}"` : '';
              return `<span class="badge ${badgeClass}" style="font-size: 0.85rem;" ${tooltipAttr}>${status}</span>`;
            };

            if (params.node.group) {
              return getBadge(params.value);
            }

            if (params.data && params.data.activities) {
              const activity = params.data.activities.find(a => a.template_id === template.id);
              const status = params.value || (activity ? activity.status : '-');
              return getBadge(status, activity ? activity.details : null);
            }
            return '-';
          },
          valueGetter: (params) => {
            if (params.data && params.data.activities) {
              const activity = params.data.activities.find(a => a.template_id === template.id);
              return activity ? activity.status : '-';
            }
          },
          valueSetter: (params) => {
            if (params.data && params.data.activities) {
              const activity = params.data.activities.find(a => a.template_id === template.id);
              if (activity) {
                activity.status = params.newValue;
                return true;
              }
            }
            return false;
          }
        });
      });
    }

    columns.push({
      field: 'investor_advisor',
      headerName: 'Advisor',
      enableRowGroup: true,
      editable: true
    });

    if (this.customFieldsValue) {
      const customFields = JSON.parse(this.customFieldsValue);
      customFields.forEach(cf => {
        const colDef = {
          field: `properties.${cf.name}`,
          headerName: cf.label,
          enableRowGroup: true,
          editable: true,
          filter: cf.field_type === 'Number' || cf.field_type === 'Money' ? 'agNumberColumnFilter' : 'agTextColumnFilter'
        };

        if (cf.field_type === 'Money' || cf.field_type === 'Number') {
          Object.assign(colDef, this.numberFormatColumn(this, colDef.field, cf.label, this.formatNumberWithCommas, 'sum', true));
        }

        columns.push(colDef);
      });
    }

    columns.push({
      field: 'deal_lead',
      headerName: 'Lead',
      filter: 'agSetColumnFilter',
      enableRowGroup: true,
      editable: true
    });

    columns.push({
      field: 'source',
      headerName: 'Source',
      filter: 'agSetColumnFilter',
      enableRowGroup: true,
      editable: true
    });

    return columns;
  }

  init(tableName) {
    console.log("DealsListAgGrid init called for table:", tableName);

    // Create a NEW gridOptions object that will be used by the base class
    this.gridOptions = {
        rowSelection: 'multiple',
        suppressRowClickSelection: true,
        onCellValueChanged: (params) => {
            console.log("onCellValueChanged", params);
            this.onCellValueChanged(params);
        },
        onSelectionChanged: () => {
            console.log("onSelectionChanged triggered");
            if (this.gridOptions && this.gridOptions.api) {
              const selectedRows = this.gridOptions.api.getSelectedRows();
              console.log("Selected rows count:", selectedRows.length);
              this.updateBulkActionsPanel(selectedRows);
            }
        },
        onVirtualColumnsChanged: this.initTooltips.bind(this),
        onBodyScroll: this.initTooltips.bind(this),
        getRowClass: (params) => {
            return '';
        }
    };

    // Override the base class's init to use our gridOptions
    // We cannot call super.init(tableName) directly if it overwrites this.gridOptions

    // Instead of calling super.init, we manually perform the steps from base_ag_grid.js init
    // but ensure our gridOptions are used.

    this.decimalPlaces = this.extractDecimalPlaces();

    // Add common properties from base class to our local gridOptions
    this.gridOptions.getRowId = params => params.data.id;
    this.gridOptions.defaultExcelExportParams = {
        columnKeys: this.getExportColumns(),
    };
    this.gridOptions.columnDefs = this.columnDefs();
    this.gridOptions.rowHeight = 90;
    this.gridOptions.suppressAggFuncInHeader = true;
    this.gridOptions.defaultColDef = {
        resizable: true,
        filter: 'agTextColumnFilter',
        sortable: true,
        minWidth: 120,
    };

    // Capture the base class's onGridReady to wrap it
    const baseOnGridReady = (event) => {
        this.gridOptions.api = event.api;
        this.gridOptions.columnApi = event.columnApi;
        this.restoreColumnVisibilityState(this.gridOptions, this.tableNameValue);
        this.gridReady();
    };

    this.gridOptions.onGridReady = (event) => {
        console.log("Grid Ready Event in DealsListAgGrid");
        baseOnGridReady(event);
    };

    this.gridOptions.onColumnVisible = (event) => {
        this.saveColumnVisibilityState(this.gridOptions, this.tableNameValue);
    };

    this.gridOptions.autoGroupColumnDef = {
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
    };

    this.gridOptions.enableRangeSelection = true;
    this.gridOptions.enableCharts = true;
    this.gridOptions.rowGroupPanelShow = 'always';
    this.gridOptions.domLayout = 'autoHeight';
    this.gridOptions.suppressDragLeaveHidesColumns = true;
    this.gridOptions.suppressMakeColumnVisibleAfterUnGroup = true;
    this.gridOptions.suppressRowGroupHidesColumns = true;
    this.gridOptions.pagination = true;
    this.gridOptions.paginationPageSize = 30;

    this.gridOptions.groupIncludeFooter = this.includeFooter();
    this.gridOptions.groupIncludeTotalFooter = this.includeTotalFooter();

    this.gridOptions.statusBar = {
        statusPanels: [
            { statusPanel: 'agSelectedRowCountComponent' },
            { statusPanel: 'agAggregationComponent' },
        ]
    };

    this.gridOptions.sideBar = {
        toolPanels: [
            {
                id: 'columns',
                labelDefault: 'Columns',
                labelKey: 'columns',
                iconKey: 'columns',
                toolPanel: 'agColumnsToolPanel',
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
    };

    console.log("Initializing grid with manually merged options:", this.gridOptions);

    let gridDiv = document.querySelector(tableName);
    this.grid = new agGrid.Grid(gridDiv, this.gridOptions);

    this.loadData();

    var api = this.gridOptions.api;
    $(document).on('turbo:before-cache', function () {
        if (api) api.destroy();
    });
  }

  updateBulkActionsPanel(selectedRows) {
    const bulkActions = document.getElementById('bulk-actions');
    const selectedCountText = document.getElementById('selected-count');

    if (bulkActions && selectedCountText) {
      if (selectedRows.length > 0) {
        bulkActions.style.display = 'flex';
        selectedCountText.innerText = `${selectedRows.length} items selected`;
      } else {
        bulkActions.style.display = 'none';
      }
    }
  }

  onCellValueChanged(params) {
    const id = params.data.id;
    const field = params.colDef.field;
    const value = params.newValue;

    if (field.startsWith('activity_')) {
      const templateId = field.split('_')[1];
      const activity = params.data.activities.find(a => a.template_id == templateId);
      if (activity) {
        this.updateActivity(activity.id, value, params);
      }
    } else {
      this.updateDealInvestor(id, field, value, params);
    }
  }

  updateDealInvestor(id, field, value, params) {
    const formData = new FormData();
    formData.append(`deal_investor[${field}]`, value);

    fetch(`/deal_investors/${id}.json`, {
      method: 'PATCH',
      headers: {
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
        'Accept': 'application/json'
      },
      body: formData
    })
    .then(response => response.json())
    .then(data => {
      console.log('DealInvestor update success:', data);
      if (field === 'status') this.refreshRowData(params.node);
    })
    .catch(error => {
      console.error('DealInvestor update failed:', error);
      params.node.setDataValue(field, params.oldValue);
    });
  }

  updateActivity(id, value, params) {
    const formData = new FormData();
    formData.append(`deal_activity[status]`, value);

    fetch(`/deal_activities/${id}.json`, {
      method: 'PATCH',
      headers: {
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
        'Accept': 'application/json'
      },
      body: formData
    })
    .then(response => response.json())
    .then(data => {
      console.log('Activity update success:', data);
      this.refreshRowData(params.node);
    })
    .catch(error => {
      console.error('Activity update failed:', error);
    });
  }

  refreshRowData(rowNode) {
    fetch(`/deal_investors/${rowNode.data.id}.json`)
      .then(response => response.json())
      .then(data => {
        rowNode.setData(data);
      });
  }

  onSelectionChanged() {
    // This is kept for compatibility if called elsewhere, but we now use updateBulkActionsPanel
    const selectedRows = this.gridOptions.api.getSelectedRows();
    this.updateBulkActionsPanel(selectedRows);
  }

  openSidepanel(event) {
    event.preventDefault();
    const id = event.currentTarget.dataset.id;
    const sidepanelElement = document.getElementById('dealInvestorSidepanel');
    const sidepanel = bootstrap.Offcanvas.getInstance(sidepanelElement) || new bootstrap.Offcanvas(sidepanelElement);
    const frame = document.getElementById('deal_investor_frame');

    frame.src = `/deal_investors/${id}?turbo_frame=deal_investor_frame`;
    sidepanel.show();
  }

  bulkNudge() {
    const selectedRows = this.gridOptions.api.getSelectedRows();
    const ids = selectedRows.map(row => row.id);
    alert(`Triggering mass nudge for IDs: ${ids.join(', ')}`);
  }

  bulkUpdateStatus() {
    const selectedRows = this.gridOptions.api.getSelectedRows();
    const newStatus = prompt("Enter new status for selected items:", "Interested");
    if (newStatus) {
      const ids = selectedRows.map(row => row.id);
      alert(`Updating status to "${newStatus}" for IDs: ${ids.join(', ')}`);
    }
  }

  gridReady() {
    console.log("Deals List AG Grid Ready with Enhanced Features");
    this.initTooltips();
  }

  initTooltips() {
    const tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
    tooltipTriggerList.map(function (tooltipTriggerEl) {
      return new bootstrap.Tooltip(tooltipTriggerEl);
    });
  }
}
