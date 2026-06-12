import BaseAgGrid from "controllers/base_ag_grid"
import moment from 'moment'
import * as bootstrap from "bootstrap"

export default class extends BaseAgGrid {
  static values = {
    dealId: Number,
    investorLabel: String,
    currency: String,
    activityTemplates: Array,
    customFields: String,
    gridColumns: String,
    dealGridColumns: Array  // [{field, label}] from deal.grid_columns_for_js
  }

  columnDefs() {
    const hardcodedFields = [
      'investor_name', 'health_score', 'status', 'stagnant',
      'tier', 'investor_advisor', 'deal_lead', 'source'
    ];

    let gridColumns = [];
    if (this.hasGridColumnsValue && this.gridColumnsValue && this.gridColumnsValue !== 'null') {
      try {
        gridColumns = JSON.parse(this.gridColumnsValue);
      } catch (e) {
        console.error("Error parsing gridColumns JSON:", e);
      }
    }

    const additionalColumns = [];
    gridColumns.forEach(col => {
      let field = col.key;
      if (field.startsWith('custom_fields.')) {
        field = field.replace('custom_fields.', 'properties.');
      }

      // Check if it's already in hardcoded fields OR an activity field
      if (hardcodedFields.includes(field) || field.startsWith('activity_')) return;

      const dataType = col.data_type ? col.data_type.toLowerCase() : '';
      const isNumeric = ['number', 'integer', 'decimal', 'money'].includes(dataType);

      // Create the additional column definition
      let colDef = {
        field: field,
        headerName: col.label,
        enableRowGroup: true,
        editable: true,
        minWidth: 150,
        filter: isNumeric ? 'agNumberColumnFilter' : (dataType === 'date' ? 'agDateColumnFilter' : 'agTextColumnFilter')
      };

      if (isNumeric) {
        colDef = { ...colDef, ...this.numberFormatColumn(this, field, col.label, this.formatNumberWithCommas, 'sum', true) };
      } else if (dataType === 'date') {
        colDef = { ...colDef, ...this.dateFormatColumn(this, field, col.label) };
      }

      additionalColumns.push(colDef);
    });

    const columns = [
      ...additionalColumns,
      {
        field: 'investor_name',
        headerName: this.investorLabelValue,
        checkboxSelection: true,
        headerCheckboxSelection: true,
        pinned: 'left',
        lockPinned: true,
        width: 350,
        minWidth: 350,
        suppressSizeToFit: true,
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
        width: 120,
        filter: 'agNumberColumnFilter',
        cellRenderer: (params) => {
          if (!params.data) return '';

          const activities = params.data.activities || [];
          const total = this.activityTemplatesValue.length;
          const completed = activities.filter(a => a.status === 'Complete').length;
          const score = total > 0 ? Math.round((completed / total) * 100) : 0;

          const missing = this.activityTemplatesValue
            .filter(t => {
              const a = activities.find(act => act.template_id === t.id);
              return !a || a.status !== 'Complete';
            })
            .map(t => t.title);

          const tooltip = missing.length > 0 ? `Pending: ${missing.join(', ')}` : 'All activities complete';

          let color = '#ef4444'; // Red
          if (score > 70) color = '#00b090'; // Green
          else if (score > 30) color = '#ffa000'; // Amber

          return `
            <div style="width: 100%; height: 100%; display: flex; align-items: center; gap: 8px;" data-bs-toggle="tooltip" title="${tooltip}">
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
        valueGetter: (params) => {
          return (params.data && params.data.stagnant) ? 'Stagnant' : '';
        },
        cellRenderer: (params) => {
          if (params.value === 'Stagnant') {
            const reason = params.data.stagnant_reason || 'No activity for more than 7 days';
            return `<span class="badge bg-danger-light" data-bs-toggle="tooltip" title="${reason}">Stagnant</span>`;
          }
          return '';
        }
      },
      {
        field: 'tier',
        headerName: 'Tier',
        filter: 'agSetColumnFilter',
        enableRowGroup: true,
        editable: true,
        cellRenderer: (params) => {
          if (!params.value) return '';
          let badgeClass = 'bg-info-light';
          const val = String(params.value);
          if (val === 'Tier 1' || val === '1') badgeClass = 'bg-primary-light';
          else if (val === 'Tier 2' || val === '2') badgeClass = 'bg-success-light';
          else if (val === 'Tier 3' || val === '3') badgeClass = 'bg-warning-light';
          else if (val === 'Tier 4' || val === '4') badgeClass = 'bg-danger-light';
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
          filter: 'agSetColumnFilter',
          cellRenderer: (params) => {
            // Group rows — plain badge only
            if (params.node.group) {
              const s = params.value;
              if (!s || s === '-' || s === 'Template') return '-';
              let bc = 'bg-secondary-light';
              if (s === 'Complete') bc = 'bg-success-light';
              if (s === 'Incomplete') bc = 'bg-danger-light';
              if (s === 'Skip') bc = 'bg-warning-light';
              return `<span class="badge ${bc}" style="font-size:0.85rem;">${s}</span>`;
            }

            if (!params.data || !params.data.activities) return '-';

            const activity = params.data.activities.find(a => a.template_id === template.id);
            if (!activity) return '-';

            const status = activity.status || 'Incomplete';
            const id = activity.id;

            let badgeClass = 'bg-secondary-light';
            if (status === 'Complete') badgeClass = 'bg-success-light';
            if (status === 'Incomplete') badgeClass = 'bg-danger-light';
            if (status === 'Skip') badgeClass = 'bg-warning-light';

            // Render a plain badge with data attributes — the floating menu
            // (appended to document.body) handles clicks via setupActivityMenu().
            const entityId = params.data.entity_id || '';
            const dealInvestorId = params.data.id || '';
            const activityName = encodeURIComponent(activity.title || '');
            return `<span class="badge ${badgeClass} activity-badge"
                          style="cursor:pointer; font-size:0.85rem;"
                          data-activity-id="${id}"
                          data-activity-status="${status}"
                          data-entity-id="${entityId}"
                          data-deal-investor-id="${dealInvestorId}"
                          data-activity-name="${activityName}">
                      ${status} <i class="ti ti-chevron-down" style="font-size:0.7rem; vertical-align:middle;"></i>
                    </span>`;
          },
          valueGetter: (params) => {
            if (params.data && params.data.activities) {
              const activity = params.data.activities.find(a => a.template_id === template.id);
              return activity ? activity.status : '-';
            }
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

    if (this.customFieldsValue && this.customFieldsValue !== 'null') {
      try {
        const customFields = JSON.parse(this.customFieldsValue);
        const gridColumnKeys = gridColumns.map(col => col.key);

        customFields.forEach(cf => {
          // Skip if already specified in grid columns (either at front or elsewhere)
          if (gridColumnKeys.includes(`custom_fields.${cf.name}`)) return;

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
      } catch (e) {
        console.error("Error parsing customFields JSON:", e);
      }
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

    // Standard money/text columns not already hardcoded above
    const moneyFields = [
      { field: 'primary_amount',         label: 'Primary Amount' },
      { field: 'secondary_investment',   label: 'Secondary Investment' },
      { field: 'pre_money_valuation',    label: 'Pre Money Valuation' },
      { field: 'fee',                    label: 'Fee' },
      { field: 'total_amount',           label: 'Total Amount' }
    ];
    moneyFields.forEach(({ field, label }) => {
      // Skip if this field was already added via gridColumns (form_type prefs)
      const alreadyAdded = columns.some(c => c.field === field);
      if (!alreadyAdded) {
        columns.push(this.numberFormatColumn(this, field, label, this.formatNumberWithCommas, 'sum', true));
      }
    });

    const textFields = [
      { field: 'company_advisor', label: 'Company Advisor' },
      { field: 'notes',           label: 'Notes' },
      { field: 'tags',            label: 'Tags' }
    ];
    textFields.forEach(({ field, label }) => {
      if (!columns.some(c => c.field === field)) {
        columns.push({ field, headerName: label, enableRowGroup: true, editable: true });
      }
    });

    // When the deal has explicit column config:
    // - Base hardcoded + activity columns always show (investor_name, status, tier …)
    // - Configured extra columns are added; unconfigured extras (primary_amount etc.) are hidden
    // - position="start" cols are inserted before the base block; position="end" after
    if (this.hasDealGridColumnsValue && this.dealGridColumnsValue.length > 0) {
      const baseFields = new Set([
        'investor_name', 'health_score', 'status', 'stagnant', 'tier',
        'investor_advisor', 'deal_lead', 'source'
      ]);
      const configuredFields = new Set(this.dealGridColumnsValue.map(c => c.field));

      // Apply custom label overrides
      this.dealGridColumnsValue.forEach(cfg => {
        if (!cfg.label) return;
        const col = columns.find(c => c.field === cfg.field);
        if (col) col.headerName = cfg.label;
      });

      // Split columns into three buckets
      const startCols = [];
      const baseCols  = [];
      const endCols   = [];

      columns.forEach(col => {
        const isBase     = baseFields.has(col.field) || col.field?.startsWith('activity_');
        const cfg        = this.dealGridColumnsValue.find(c => c.field === col.field);
        const inConfig   = !!cfg;
        const position   = cfg?.position || 'end';

        if (isBase) {
          baseCols.push(col);
        } else if (inConfig) {
          (position === 'start' ? startCols : endCols).push(col);
        }
        // unconfigured extras are dropped
      });

      return [...startCols, ...baseCols, ...endCols];
    }

    return columns;
  }

  init(tableName) {
    console.log("DealsListAgGrid init called for table:", tableName);
    window.DealsGrid = this;

    // Create a NEW gridOptions object that will be used by the base class
    this.gridOptions = {
        rowSelection: 'multiple',
        suppressRowClickSelection: true,
        onCellValueChanged: (params) => {
            console.log("onCellValueChanged", params);
            this.onCellValueChanged(params);
        },
        onFilterChanged: () => {
            console.log("onFilterChanged triggered");
            this.updateFilterVisuals();
        },
        onSelectionChanged: () => {
            console.log("onSelectionChanged triggered");
            if (this.gridOptions && this.gridOptions.api) {
              const selectedRows = this.gridOptions.api.getSelectedRows();
              console.log("Selected rows count:", selectedRows.length);
              this.updateBulkActionsPanel(selectedRows);
            }
        },
        onVirtualColumnsChanged: () => { this.initTooltips(); this.setRowIds(); },
        onBodyScroll: () => { this.initTooltips(); this.setRowIds(); },
        onFirstDataRendered: () => { this.setRowIds(); },
        getRowClass: (params) => {
            return params.data && params.data.id ? `deal_investor_${params.data.id}` : '';
        }
    };

    // Override the base class's init to use our gridOptions
    // We cannot call super.init(tableName) directly if it overwrites this.gridOptions

    // Instead of calling super.init, we manually perform the steps from base_ag_grid.js init
    // but ensure our gridOptions are used.

    this.decimalPlaces = this.extractDecimalPlaces();

    // Add common properties from base class to our local gridOptions
    this.gridOptions.getRowId = params => {
      if (params.data && params.data.id) {
        return `deal_investor_${params.data.id}`;
      }
      return params.data?.id;
    };
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

    const isMobile = window.innerWidth < 768;

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
    this.gridOptions.domLayout = isMobile ? 'normal' : 'autoHeight';
    this.gridOptions.suppressHorizontalScroll = false;
    this.gridOptions.suppressDragLeaveHidesColumns = true;
    this.gridOptions.suppressMakeColumnVisibleAfterUnGroup = true;
    this.gridOptions.suppressRowGroupHidesColumns = true;
    this.gridOptions.pagination = true;
    this.gridOptions.paginationPageSize = 30;

    if (isMobile) {
      this.gridOptions.columnDefs.forEach(col => {
        if (col.pinned) col.pinned = null;
        if (col.field === 'investor_name') col.width = 250;
      });
    }

    this.gridOptions.onGridSizeChanged = (params) => {
      // params.api.sizeColumnsToFit();
    };

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
    const modalCount = document.getElementById('bulk-advance-count');

    if (bulkActions && selectedCountText) {
      if (selectedRows.length > 0) {
        bulkActions.style.display = 'flex';
        selectedCountText.innerText = `${selectedRows.length} items selected`;
        if (modalCount) modalCount.innerText = selectedRows.length;
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

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
    const headers = {
      'Accept': 'application/json'
    };
    if (csrfToken) headers['X-CSRF-Token'] = csrfToken;

    fetch(`/deal_investors/${id}.json`, {
      method: 'PATCH',
      headers: headers,
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

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
    const headers = {
      'Accept': 'application/json'
    };
    if (csrfToken) headers['X-CSRF-Token'] = csrfToken;

    fetch(`/deal_activities/${id}.json`, {
      method: 'PATCH',
      headers: headers,
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

  // Called from the inline dropdown in activity cells.
  updateActivityStatus(id, newStatus) {
    const formData = new FormData();
    formData.append('deal_activity[status]', newStatus);

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
    const headers = { 'Accept': 'application/json' };
    if (csrfToken) headers['X-CSRF-Token'] = csrfToken;

    fetch(`/deal_activities/${id}.json`, {
      method: 'PATCH',
      headers,
      body: formData
    })
    .then(r => r.json())
    .then(() => {
      // Refresh the row that owns this activity
      if (this.gridOptions && this.gridOptions.api) {
        this.gridOptions.api.forEachNode(node => {
          if (node.data && node.data.activities && node.data.activities.find(a => a.id === id)) {
            this.refreshRowData(node);
          }
        });
      }
    })
    .catch(err => console.error('Activity status update failed:', err));
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

  updateFilterVisuals() {
    const filterModel = this.gridOptions.api.getFilterModel();
    const hasFilters = Object.keys(filterModel).length > 0;

    // Update cards visual state
    document.querySelectorAll('.analytics-card').forEach(card => {
      card.classList.remove('border-primary', 'bg-primary-subtle', 'shadow-sm');
      card.style.transform = 'scale(1)';
    });

    if (hasFilters) {
      if (filterModel.status) {
        const activeCard = document.querySelector('[data-action*="filterActive"]')?.closest('.analytics-card');
        if (activeCard) {
          activeCard.classList.add('border-primary', 'bg-primary-subtle', 'shadow-sm');
          activeCard.style.transform = 'scale(1.02)';
        }
      }
      if (filterModel.stagnant) {
        const stagnantCard = document.querySelector('[data-action*="filterStagnant"]')?.closest('.analytics-card');
        if (stagnantCard) {
          stagnantCard.classList.add('border-primary', 'bg-primary-subtle', 'shadow-sm');
          stagnantCard.style.transform = 'scale(1.02)';
        }
      }
    }

    // Show/Hide Clear Filter Button
    const clearBtn = document.getElementById('clear-grid-filters');
    if (clearBtn) {
      clearBtn.style.display = hasFilters ? 'inline-flex' : 'none';
    }
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

  addInvestor(event) {
    event.preventDefault();
    const url = event.currentTarget.href;
    const sidepanelElement = document.getElementById('dealInvestorSidepanel');
    const sidepanel = bootstrap.Offcanvas.getInstance(sidepanelElement) || new bootstrap.Offcanvas(sidepanelElement);
    const frame = document.getElementById('deal_investor_frame');

    frame.src = url;
    sidepanel.show();
  }

  appendNewRow(data) {
    console.log("DealsListAgGrid#appendNewRow called", data);
    if (this.gridOptions && this.gridOptions.api) {
      try {
        // Ensure data has the correct structure if needed
        this.gridOptions.api.applyTransaction({ add: [data], addIndex: 0 });
        console.log("Row appended successfully via applyTransaction");
      } catch (e) {
        console.error("applyTransaction failed, trying updateRowData", e);
        try {
          this.gridOptions.api.updateRowData({ add: [data], addIndex: 0 });
        } catch (e2) {
          console.error("updateRowData also failed", e2);
        }
      }

      // Close sidepanel after successful save
      const sidepanelElement = document.getElementById('dealInvestorSidepanel');
      if (sidepanelElement) {
        // Force hide using multiple methods
        try {
          const bsOffcanvas = bootstrap.Offcanvas.getInstance(sidepanelElement) || new bootstrap.Offcanvas(sidepanelElement);
          bsOffcanvas.hide();
        } catch (e) {
          console.error("Bootstrap hide failed", e);
        }

        // jQuery fallback if available
        if (window.jQuery && jQuery.fn.offcanvas) {
          try {
            jQuery(sidepanelElement).offcanvas('hide');
          } catch (e) {}
        }

        // Final fallback: click the close button
        setTimeout(() => {
          if (sidepanelElement.classList.contains('show')) {
            const closeBtn = sidepanelElement.querySelector('.btn-close');
            if (closeBtn) closeBtn.click();
          }
        }, 100);
      }
    } else {
      console.error("Grid API not found in appendNewRow");
    }
  }

  bulkNudge() {
    const selectedRows = this.gridOptions.api.getSelectedRows();
    const ids = selectedRows.map(row => row.id);
    alert(`Triggering mass nudge for IDs: ${ids.join(', ')}`);
  }

  bulkUpdateStatus() {
    // Opens the Bootstrap modal — triggered by data-bs-toggle on the button
    const selectedRows = this.gridOptions.api.getSelectedRows();
    const countEl = document.getElementById('bulk-advance-count');
    if (countEl) countEl.innerText = selectedRows.length;
  }

  confirmBulkUpdateStatus() {
    this.confirmBulkAdvanceActivity();
  }

  bulkAdvanceActivity() {
    const selectedRows = this.gridOptions.api.getSelectedRows();
    const countEl = document.getElementById('bulk-advance-count');
    if (countEl) countEl.innerText = selectedRows.length;
  }

  confirmBulkAdvanceActivity() {
    const selectedRows = this.gridOptions.api.getSelectedRows();
    console.log("[confirmBulkAdvanceActivity] selectedRows count:", selectedRows.length);
    console.log("[confirmBulkAdvanceActivity] selectedRows:", selectedRows);
    if (selectedRows.length === 0) {
      console.warn("[confirmBulkAdvanceActivity] No rows selected, aborting.");
      return;
    }

    // Close the modal
    const modal = bootstrap.Modal.getInstance(document.getElementById('bulkAdvanceActivityModal'));
    if (modal) modal.hide();

    const ids = selectedRows.map(row => row.id);
    console.log("[confirmBulkAdvanceActivity] ids to advance:", ids);
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;

    fetch('/deal_investors/bulk_advance_activity', {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-CSRF-Token': csrfToken
      },
      body: JSON.stringify({ ids: ids })
    })
    .then(response => {
      console.log("[confirmBulkAdvanceActivity] response status:", response.status);
      return response.json();
    })
    .then(data => {
      console.log("[confirmBulkAdvanceActivity] response data:", data);
      if (data.success) {
        console.log(`Bulk advance: ${data.advanced_count} investor(s) moved to next activity`);
        if (data.errors && data.errors.length > 0) {
          alert(`Advanced ${data.advanced_count} investor(s).\nWarnings:\n${data.errors.join('\n')}`);
        }
        this.loadData();
      } else {
        alert(`Error: ${data.error}`);
      }
    })
    .catch(error => {
      console.error('[confirmBulkAdvanceActivity] fetch failed:', error);
      alert('Bulk advance failed. Please try again.');
    });
  }

  gridReady() {
    console.log("Deals List AG Grid Ready with Enhanced Features");
    this.initTooltips();
    this.setupActivityMenu();
    this.updateFilterVisuals();

    // Listen for chart point clicks dispatched by charts_handler.js via the global
    // Highcharts event. No timing/polling needed — the handler fires on any click.
    this._chartFilterHandler = (e) => this.filterByChart(e.detail.type, e.detail.value);
    document.addEventListener('chart:grid-filter', this._chartFilterHandler);

    // Wire the Bulk Advance Activity confirm button directly, since the modal
    // may be outside the Stimulus controller's DOM scope when Bootstrap moves it.
    const confirmBtn = document.getElementById('bulk-advance-confirm-btn');
    if (confirmBtn) {
      confirmBtn.addEventListener('click', () => this.confirmBulkAdvanceActivity());
    }

    // Update the count in the modal each time it opens
    const advanceModal = document.getElementById('bulkAdvanceActivityModal');
    if (advanceModal) {
      advanceModal.addEventListener('show.bs.modal', () => {
        const selectedRows = this.gridOptions.api.getSelectedRows();
        const countEl = document.getElementById('bulk-advance-count');
        if (countEl) countEl.innerText = selectedRows.length;
      });
    }
  }

  disconnect() {
    if (this._chartFilterHandler) {
      document.removeEventListener('chart:grid-filter', this._chartFilterHandler);
    }
  }

  // Build a single floating menu appended to document.body so it is never clipped
  // by AG Grid's overflow:hidden cells or the horizontal-scroll viewport.
  setupActivityMenu() {
    // Reuse an existing menu if the controller is re-initialized (turbo navigation)
    let menu = document.getElementById('deals-activity-floating-menu');
    if (!menu) {
      menu = document.createElement('div');
      menu.id = 'deals-activity-floating-menu';
      menu.className = 'dropdown-menu shadow-sm show';
      menu.style.cssText = 'position:fixed;z-index:99999;display:none;min-width:150px;';
      menu.innerHTML = `
        <button class="dropdown-item" type="button" data-status="complete">
          <i class="ti ti-circle-check text-success me-2"></i>Complete
        </button>
        <button class="dropdown-item" type="button" data-status="incomplete">
          <i class="ti ti-circle-x text-danger me-2"></i>Incomplete
        </button>
        <button class="dropdown-item" type="button" data-status="skip">
          <i class="ti ti-minus text-warning me-2"></i>Skip
        </button>
        <hr class="dropdown-divider">
        <a class="dropdown-item" id="deals-activity-menu-show" href="#">
          <i class="ti ti-eye me-2"></i>View Activity
        </a>
        <a class="dropdown-item" id="deals-activity-menu-docs" href="#">
          <i class="ti ti-upload me-2"></i>Upload Docs
        </a>
      `;
      document.body.appendChild(menu);

      // Status button clicks
      menu.querySelectorAll('[data-status]').forEach(btn => {
        btn.addEventListener('click', (e) => {
          e.stopPropagation();
          const id = parseInt(menu.dataset.activityId);
          if (id) this.updateActivityStatus(id, btn.dataset.status);
          menu.style.display = 'none';
        });
      });
    }

    // Delegate: open menu when any .activity-badge is clicked
    document.addEventListener('click', (e) => {
      const badge = e.target.closest('.activity-badge');

      if (badge) {
        e.stopPropagation();
        const id = parseInt(badge.dataset.activityId);
        const backTo = encodeURIComponent(window.location.href);

        menu.dataset.activityId = id;
        menu.querySelector('#deals-activity-menu-show').href = `/deal_activities/${id}`;
        const entityId = badge.dataset.entityId;
        const dealInvestorId = badge.dataset.dealInvestorId;
        const activityName = badge.dataset.activityName || '';
        // Upload doc owner is DealInvestor; name preset to the deal activity title
        menu.querySelector('#deals-activity-menu-docs').href = `/documents/new?document[owner_id]=${dealInvestorId}&document[owner_type]=DealInvestor&document[entity_id]=${entityId}&document[name]=${activityName}&back_to=${backTo}`;

        // Position menu below the badge using viewport coordinates
        const rect = badge.getBoundingClientRect();
        let left = rect.left;
        let top = rect.bottom + 4;

        // Prevent overflow off right edge
        if (left + 180 > window.innerWidth) left = window.innerWidth - 185;
        // Prevent overflow off bottom edge
        if (top + 220 > window.innerHeight) top = rect.top - 224;

        menu.style.left = `${left}px`;
        menu.style.top = `${top}px`;
        menu.style.display = 'block';
        return;
      }

      // Click anywhere outside the menu closes it
      if (!menu.contains(e.target)) {
        menu.style.display = 'none';
      }
    });
  }

  initTooltips() {
    const tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
    tooltipTriggerList.map(function (tooltipTriggerEl) {
      return new bootstrap.Tooltip(tooltipTriggerEl);
    });
  }

  clearFilters() {
    this.gridOptions.api.setFilterModel(null);
  }

  filterActive() {
    this.gridOptions.api.setFilterModel({
      status: {
        filterType: 'set',
        values: ['Active', 'Committed', 'Complete']
      }
    });
  }

  filterStagnant() {
    this.gridOptions.api.setFilterModel({
      stagnant: {
        filterType: 'text',
        type: 'contains',
        filter: 'Stagnant'
      }
    });
  }

  filterByChart(chartType, value) {
    console.log("Filtering by chart:", chartType, value);
    if (!this.gridOptions.api) return;

    let filterModel = {};

    if (chartType === 'status') {
      filterModel.status = { filterType: 'set', values: [value] };

    } else if (chartType === 'source') {
      const filterValue = (value === 'Unknown' || value === 'null' || value === '') ? null : value;
      filterModel.source = { filterType: 'set', values: [filterValue] };

    } else if (chartType === 'deal_lead') {
      const filterValue = (value === 'Unknown' || value === 'null' || value === '') ? null : value;
      filterModel.deal_lead = { filterType: 'set', values: [filterValue] };

    } else if (chartType === 'tier') {
      const filterValue = (value === 'Unknown' || value === 'null' || value === '') ? null : value;
      filterModel.tier = { filterType: 'set', values: [filterValue] };

    } else if (chartType === 'days_in_stage') {
      if (value === '0-7 days') {
        // Recently active investors — clear all filters to show the full list
        this.gridOptions.api.setFilterModel({});
        this.updateFilterVisuals();
        this.scrollToGrid();
        return;
      } else {
        // 8-14, 15-30, 30+ days — show stagnant investors
        this.filterStagnant();
        return;
      }

    } else if (chartType === 'activity_status') {
      if (value === 'Complete') {
        filterModel.health_score = { filterType: 'number', type: 'equals', filter: 100 };
      } else if (value === 'Incomplete' || value === 'Skip') {
        filterModel.health_score = { filterType: 'number', type: 'lessThan', filter: 100 };
      }
    }

    this.gridOptions.api.setFilterModel(filterModel);
    this.updateFilterVisuals();
    this.scrollToGrid();
  }

  scrollToGrid() {
    const gridElement = document.querySelector(this.tableNameValue);
    if (gridElement) {
      gridElement.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  }

  setRowIds() {
    if (!this.gridOptions || !this.gridOptions.api) return;
    this.gridOptions.api.forEachNode(node => {
      if (node.id) {
        const element = document.querySelector(`[row-id="${node.id}"]`);
        if (element && !element.id) {
          element.id = node.id;
        }
      }
    });
  }
}
