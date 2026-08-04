import BaseAgGrid from "controllers/base_ag_grid"
import moment from 'moment'
import * as bootstrap from "bootstrap"

// Row-menu actions that open the offcanvas on a specific tab with that tab's
// "new" form already popped. panePrefix/frameId mirror the ids rendered by
// deal_investors/_deal_investor_deal_details.html.erb, where the pane ids carry a
// "-di-<deal_investor id>" suffix to stay unique against the deal's own tab strip
// on the same page — the concrete id is built in openPanelWithPendingAction().
const PANEL_ACTIONS = {
  new_task: { panePrefix: "tasks-tab", tabFrameId: "tasks_frame", newRecordFrameId: "new_task" },
  new_note: { panePrefix: "notes-tab", tabFrameId: "notes_frame", newRecordFrameId: "new_note" }
};

export default class extends BaseAgGrid {
  static targets = ["search"]

  static values = {
    dealId: Number,
    investorLabel: String,
    currency: String,
    activityTemplates: Array,
    customFields: String,
    gridColumns: String,
    dealGridColumns: Array,  // [{field, label}] from deal.grid_columns_for_js
    dealInvestorStatuses: String
  }

  statusOptions() {
    const fallbackStatuses = ['New', 'Interested', 'In Progress', 'Committed', 'Complete', 'Declined'];

    if (!this.hasDealInvestorStatusesValue) return fallbackStatuses;

    const raw = this.dealInvestorStatusesValue;
    let statuses = [];

    if (Array.isArray(raw)) {
      statuses = raw;
    } else if (typeof raw === 'string') {
      const trimmed = raw.trim();
      if (!trimmed) return fallbackStatuses;

      const normalized = trimmed.replace(/^['\"]+|['\"]+$/g, '');

      // Support either JSON arrays or comma-separated strings from deal.json_fields.
      if (normalized.startsWith('[')) {
        try {
          const parsed = JSON.parse(normalized);
          if (Array.isArray(parsed)) statuses = parsed;
        } catch (_e) {
          statuses = normalized.split(',');
        }
      } else {
        statuses = normalized.split(',');
      }
    }

    const cleanedStatuses = statuses
      .map((status) => String(status).trim().replace(/^['\"]+|['\"]+$/g, ''))
      .filter((status) => status.length > 0);

    return cleanedStatuses.length ? cleanedStatuses : fallbackStatuses;
  }

  // Common method to check user has permission to update the row
  canUpdateRow(data) {
    return !!(data && data.can_update);
  }

  // Common method to show Access Denied message for user_alert configured on the page
  showAccessDenied(message = 'Access denied: you do not have permission to update this deal investor.') {
    const now = Date.now();
    if (this._lastAccessDeniedAt && (now - this._lastAccessDeniedAt) < 1500) return;
    this._lastAccessDeniedAt = now;

    const host = document.getElementById('user_alert');
    if (!host) {
      alert(message);
      return;
    }

    host.innerHTML = `
      <div id="page_alerts" class="page_alerts">
        <div class="alert alert-danger alert-dismissible border-0 fade show" role="alert">
          ${message}
          <button type="button" class="btn-close btn-close-white" data-bs-dismiss="alert" aria-label="Close"></button>
        </div>
      </div>
    `;

    // Timeout to let the turbo frame load completely for multiple turbo messages
    setTimeout(() => {
      const alertEl = host.querySelector('.alert');
      if (!alertEl) return;
      const dismiss = alertEl.querySelector('[data-bs-dismiss="alert"]');
      if (dismiss) {
        dismiss.click();
      } else {
        alertEl.remove();
      }
    }, 4000);
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
        wrapText: true,
        // Opts this column into the quick filter (defaultColDef opts every other
        // one out). Tags are included so searching a tag surfaces the row too.
        getQuickFilterText: (params) => [params.value, params.data?.tags].filter(Boolean).join(' '),
        cellRenderer: (params) => {
          if (params.data) {
            const logoUrl = params.data.investor_logo_url;
            const initials = params.data.investor_initials || '??';
            const tags = params.data.tags || '';

            const avatarHtml = logoUrl
              ? `<img src="${logoUrl}" class="rounded-circle" alt="user" width="50" height="50">`
              : `<div class="rounded-circle bg-light d-flex align-items-center justify-content-center text-muted fw-bold" style="width: 50px; height: 50px;">${initials}</div>`;

            const tagsHtml = tags.split(',').map(tag => tag.trim()).filter(tag => tag !== '').map(tag => {
              const url = new URL(window.location.href);
              url.searchParams.set('q[tags_cont]', tag);
              return `<a href="${url.toString()}" class="badge rounded-pill bg-info-subtle text-primary border-info-subtle me-1 mb-1" style="font-weight: 500; text-decoration: none; font-size: 0.75rem !important; padding: 0.2rem 0.5rem !important;">${tag}</a>`;
            }).join('');

            // dont need to shoe remarks tooltip anymore
            // The row-actions caret carries no data-action: setupRowActionsMenu()
            // handles it with a delegated listener, since the menu it opens lives
            // on document.body. can_update rides along so the menu can hide Edit.
            return `
              <div class="d-flex flex-row comment-row w-100" style="white-space: normal !important; line-height: 1.2; padding: 12px 16px; gap: 12px; height: 100%;">
                <div class="flex-shrink-0 d-flex align-items-center">
                  <span>${avatarHtml}</span>
                </div>
                <div class="comment-text w-100 d-flex flex-column justify-content-center">
                  <div class="d-flex align-items-center mb-1">
                    <h6 class="fw-medium mb-0 me-2">
                      <a href="#" data-action="click->deals-list-ag-grid#openSidepanel" data-id="${params.data.id}" class="text-dark">${params.value}</a>
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
                <div class="flex-shrink-0 d-flex align-items-center ms-auto">
                  <a href="#"
                     class="btn btn-outline-primary deals-row-actions"
                     data-id="${params.data.id}"
                     data-can-update="${params.data.can_update}"
                     aria-label="Row actions"
                     title="Actions">
                    <i class="fa-solid fa-caret-down" aria-hidden="true"></i>
                  </a>
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
          values: this.statusOptions()
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
            const canUpdate = this.canUpdateRow(params.data);
            const chevron = canUpdate ? '<i class="ti ti-chevron-down" style="font-size:0.7rem; vertical-align:middle;"></i>' : '';

            return `<span class="badge ${badgeClass} activity-badge"
                          style="cursor:pointer; font-size:0.85rem;"
                          data-activity-id="${id}"
                          data-activity-status="${status}"
                          data-entity-id="${entityId}"
                          data-deal-investor-id="${dealInvestorId}"
                          data-activity-name="${activityName}"
                          data-can-update="${canUpdate}">
                      ${status} ${chevron}
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

    // The grid's default order comes from the server sorted on this date, so showing
    // it keeps the row order self-explanatory. Read-only: it is derived from notes'
    // "On" dates and completed tasks, never typed in here.
    if (!columns.some(c => c.field === 'last_interaction_date')) {
      columns.push(this.dateFormatColumn(this, 'last_interaction_date', 'Last Interaction'));
    }

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

      // Preserve the order the user set in the form (dealGridColumnsValue array order)
      const configIndex = (col) => this.dealGridColumnsValue.findIndex(c => c.field === col.field);
      startCols.sort((a, b) => configIndex(a) - configIndex(b));
      endCols.sort((a, b) => configIndex(a) - configIndex(b));

      return [...startCols, ...baseCols, ...endCols];
    }

    return columns;
  }

  init(tableName) {
    console.log("DealsListAgGrid init called for table:", tableName);
    window.DealsGrid = this;

    // Create a NEW gridOptions object that will be used by the base class
    // We remove the range selection and cell focus features to avoid the persistent blue highlight on cells.
    this.gridOptions = {
        rowSelection: 'multiple',
        suppressRowClickSelection: true,
        suppressCellFocus: true,
        suppressRowHoverHighlight: true,
        suppressRangeSelection: true,
        enableRangeSelection: false,
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
        onFirstDataRendered: (event) => {
          this.ensureFirstRowVisible(event);
          this.initTooltips();
          this.setRowIds();
        },
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
        // Quick filter searches the investor name only; columns opt in by
        // overriding this (see investor_name in columnDefs).
        getQuickFilterText: () => '',
    };
    // Search text is built once per row instead of on every keystroke.
    this.gridOptions.cacheQuickFilter = true;

    // Capture the base class's onGridReady to wrap it
    const baseOnGridReady = (event) => {
        this.gridOptions.api = event.api;
        this.gridOptions.columnApi = event.columnApi;
      this.configureFixedLayoutFixes();
        this.restoreColumnVisibilityState(this.gridOptions, this.tableNameValue);
        this.gridReady();
      this.refreshGridLayout(event);
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

    // NOTE: enableRangeSelection/enableCharts are intentionally NOT enabled here.
    // This grid disables range selection & cell focus highlighting above
    // (suppressCellFocus, suppressRangeSelection, enableRangeSelection: false)
    // to avoid the persistent blue range-selection highlight on cells. Charts
    // aren't used on this grid, and enableCharts requires range selection to
    // be enabled, so both are left off.
    this.gridOptions.rowGroupPanelShow = 'always';
    this.gridOptions.domLayout = 'normal';
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
    this.gridElement = gridDiv;
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
    if (this._suppressCellValueChanged) return;

    const id = params.data.id;
    const field = params.colDef.field;
    const value = params.newValue;

    if (!this.canUpdateRow(params.data)) {
      this.showAccessDenied();
      // Revert immediately for read-only rows without triggering another update loop.
      if (typeof params.oldValue !== 'undefined' && params.oldValue !== value) {
        this._suppressCellValueChanged = true;
        params.node.setDataValue(field, params.oldValue);
        setTimeout(() => { this._suppressCellValueChanged = false; }, 0);
      }
      return;
    }

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

  // Hook for sending Deal Investor Updates to the server
  updateDealInvestor(id, field, value, params) {
    if (!this.canUpdateRow(params.data)) {
      this.showAccessDenied();
      return;
    }

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
    .then(response => {
      if (!response.ok || response.redirected) throw new Error(`DealInvestor update failed: HTTP ${response.status}`);
      return response.json();
    })
    .then(data => {
      console.log('DealInvestor update success:', data);
      if (field === 'status') this.refreshRowData(params.node);
    })
    .catch(error => {
      console.error('DealInvestor update failed:', error);
      // Prevent setDataValue from re-triggering a recursive update loop.
      this._suppressCellValueChanged = true;
      params.node.setDataValue(field, params.oldValue);
      setTimeout(() => { this._suppressCellValueChanged = false; }, 0);
    });
  }

  updateActivity(id, value, params) {
    if (!this.canUpdateRow(params.data)) {
      this.showAccessDenied();
      return;
    }

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
    .then(response => {
      if (!response.ok || response.redirected) throw new Error(`Activity update failed: HTTP ${response.status}`);
      return response.json();
    })
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
    // Do not attempt status updates from read-only users.
    if (this._activityMenuCanUpdate !== true) {
      this.showAccessDenied();
      return;
    }

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
    .then(r => {
      if (!r.ok || r.redirected) throw new Error(`Activity status update failed: HTTP ${r.status}`);
      return r.json();
    })
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
    // The quick filter is not part of the filter model, so it is checked
    // separately — otherwise searching would leave the clear "x" hidden.
    const hasSearchTerm = this.hasSearchTarget && this.searchTarget.value.trim().length > 0;
    const hasFilters = Object.keys(filterModel).length > 0 || hasSearchTerm;

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

  // Investor-name click. The URL building moved into showSidepanel() so the row
  // menu's actions below can reuse it.
  openSidepanel(event) {
    event.preventDefault();
    event.stopPropagation();
    this.showSidepanel(`/deal_investors/${event.currentTarget.dataset.id}?turbo_frame=deal_investor_frame`);
  }

  // Tears down the per-open 'hidden.bs.offcanvas' handler and aborts any in-flight
  // fetch from loadSidepanelContent(). Called before every re-open and on
  // disconnect so handlers/requests from a previous open never fire against the
  // panel's new state.
  cleanupSidepanelListeners() {
    const sidepanelElement = this.sidepanelElement;

    if (this._sidepanelHideHandler && sidepanelElement) {
      sidepanelElement.removeEventListener('hidden.bs.offcanvas', this._sidepanelHideHandler);
    }

    if (this._sidepanelLoadController) {
      this._sidepanelLoadController.abort();
      this._sidepanelLoadController = null;
    }

    this._sidepanelHideHandler = null;
  }

  // Forces the offcanvas back to a fully-closed DOM/body state before reopening it.
  // Needed because the panel can be reopened (e.g. clicking a different investor)
  // before Bootstrap's own hide() transition/backdrop cleanup has finished, which
  // otherwise leaves stray backdrops and body classes/styles behind.
  resetSidepanelState() {
    const sidepanelElement = this.sidepanelElement;
    if (!sidepanelElement) return;

    const existingInstance = bootstrap.Offcanvas.getInstance(sidepanelElement);
    if (existingInstance) {
      try { existingInstance.dispose(); } catch (_error) {}
    }

    sidepanelElement.classList.remove('show', 'hiding');
    sidepanelElement.removeAttribute('aria-hidden');
    sidepanelElement.style.display = '';
    document.body.classList.remove('offcanvas-open');
    document.body.style.removeProperty('overflow');
    // Bootstrap's ScrollBarHelper adds an inline body padding-right on show() to
    // offset the hidden scrollbar, caching the prior value in data-bs-padding-right
    // to restore on hide(). Disposing the instance here skips that restore (we
    // never let hide()'s transition-queued callback run), so without clearing it
    // manually each reopen stacks another scrollbar-width on top of the last.
    document.body.style.removeProperty('padding-right');
    document.body.removeAttribute('data-bs-padding-right');
    document.querySelectorAll('.offcanvas-backdrop').forEach((backdrop) => backdrop.remove());
  }

  // The offcanvas body is now a plain <div> (see _list_view_sidepanel.html.erb),
  // not a <turbo-frame>, because loadSidepanelContent() populates it via a manual
  // fetch rather than Turbo's frame navigation - see that method for why.
  get sidepanelContentContainer() {
    return document.getElementById('deal_investor_panel_content');
  }

  // Resets the panel body back to its loading spinner between opens/closes so
  // stale content from the previous investor is never visible while new content loads.
  resetSidepanelFrame() {
    const container = this.sidepanelContentContainer;
    if (!container) return null;

    container.innerHTML = `
      <div class="p-4 text-center">
        <div class="spinner-border text-primary" role="status">
          <span class="visually-hidden">Loading...</span>
        </div>
      </div>
    `;

    return container;
  }

  // Fetches fresh HTML directly rather than relying on a persistent Turbo frame's
  // src assignment, since the previous investor's navigation state (e.g. having
  // followed a link inside the panel) could otherwise leak into the next open.
  // Stale in-flight loads are aborted so an older investor's response cannot
  // overwrite a newer one, and onLoaded only fires once the right content lands.
  loadSidepanelContent(url, onLoaded) {
    const container = this.sidepanelContentContainer;
    if (!container) return;

    if (this._sidepanelLoadController) {
      this._sidepanelLoadController.abort();
    }

    this._sidepanelLoadController = new AbortController();
    const controller = this._sidepanelLoadController;

    this.resetSidepanelFrame();

    fetch(url, {
      method: 'GET',
      headers: { Accept: 'text/html' },
      signal: controller.signal
    })
      .then((response) => {
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        return response.text();
      })
      .then((html) => {
        if (controller.signal.aborted) return;
        container.innerHTML = html;
        if (typeof onLoaded === 'function') onLoaded();
      })
      .catch((error) => {
        if (controller.signal.aborted) return;
        console.error('Failed to load deal investor sidepanel content', error);
        container.innerHTML = '<div class="p-4 text-danger">Unable to load investor details.</div>';
        if (typeof onLoaded === 'function') onLoaded();
      });
  }

  // Explicit close path used by the "All Documents" link (which navigates the
  // grid page away via turbo_frame: "_top") and turbo:before-visit below, so the
  // panel doesn't linger open/half-torn-down across a full-page Turbo navigation.
  closeSidepanel() {
    const sidepanelElement = this.sidepanelElement;
    if (!sidepanelElement) return;

    try {
      const sidepanel = bootstrap.Offcanvas.getInstance(sidepanelElement) || new bootstrap.Offcanvas(sidepanelElement);
      this.cleanupSidepanelListeners();
      this.resetSidepanelState();
      this.resetSidepanelFrame();
      sidepanel.hide();
      this.clearGridHighlight();
    } catch (error) {
      console.error('Failed to hide deal investor sidepanel', error);
    }
  }

  // Loads url into the offcanvas panel and slides it open.
  // Close the sidepanel by clicking the "x" or the default Bootstrap backdrop
  // (non-static offcanvas already dismisses on backdrop click). We deliberately
  // don't attach our own document-level click listener here — an earlier
  // attempt at that intercepted/raced with clicks on the grid and was unreliable.
  // onContentLoaded, when given, runs once the fetched HTML is in the panel and
  // the panel has been told to open — see openPanelWithPendingAction().
  showSidepanel(url, onContentLoaded) {
    const sidepanelElement = document.getElementById('dealInvestorSidepanel');
    if (!sidepanelElement) return;

    this.resetSidepanelState();
    this.cleanupSidepanelListeners();

    const sidepanel = bootstrap.Offcanvas.getOrCreateInstance(sidepanelElement);
    const container = this.resetSidepanelFrame();
    if (!container) return;

    this._sidepanelHideHandler = () => {
      this.cleanupSidepanelListeners();
      this.resetSidepanelFrame();
      this.clearGridHighlight();
    };

    sidepanelElement.addEventListener('hidden.bs.offcanvas', this._sidepanelHideHandler);

    const frameUrl = `${url}${url.includes('?') ? '&' : '?'}_=${Date.now()}`;
    this.loadSidepanelContent(frameUrl, () => {
      requestAnimationFrame(() => {
        sidepanel.show();
        if (typeof onContentLoaded === 'function') onContentLoaded();
      });
    });
  }

  // Read-only panel — same as clicking the investor name.
  viewInvestor(id) {
    this.showSidepanel(`/deal_investors/${id}?turbo_frame=deal_investor_frame`);
  }

  // Skips the extra "Edit" click: the panel opens straight into the form.
  editInvestor(id) {
    this.showSidepanel(`/deal_investors/${id}/edit?turbo_frame=deal_investor_frame`);
  }

  // Opens the panel, switches to a tab and pops that tab's "new" form. Tasks and
  // Notes work identically: the panel content lands first (which is when the tab
  // is revealed), then the tab's lazy frame loads, and the turbo:frame-load
  // listener wired up in gridReady() pops the form — no timers involved.
  newTaskForInvestor(id) {
    this.openPanelWithPendingAction(id, PANEL_ACTIONS.new_task);
  }

  newNoteForInvestor(id) {
    this.openPanelWithPendingAction(id, PANEL_ACTIONS.new_note);
  }

  // Records what to do once the tab's frame arrives, then opens the panel and
  // reveals the tab as soon as its markup lands. The tab has to be revealed here
  // rather than off a turbo:frame-load for the enclosing "deal_investor_frame":
  // loadSidepanelContent() injects that frame via innerHTML with no src, and a
  // frame that never loads a source never fires turbo:frame-load.
  openPanelWithPendingAction(id, action) {
    const pendingAction = { ...action, paneId: `${action.panePrefix}-di-${id}` };
    this._pendingPanelAction = pendingAction;
    clearTimeout(this._pendingPanelActionTimer);
    // Give up if a frame never loads, so a later panel open is not hijacked.
    this._pendingPanelActionTimer = setTimeout(() => { this._pendingPanelAction = null; }, 15000);
    this.showSidepanel(
      `/deal_investors/${id}?turbo_frame=deal_investor_frame`,
      () => this.openPanelTab(pendingAction.paneId)
    );
  }

  // Everything below is scoped to the offcanvas on purpose: this page also
  // renders the deal-level details partial, which has its own #tasks-tab pane
  // and its own turbo-frame called "tasks_frame". Selecting them globally would
  // resolve by source order rather than by intent.
  get sidepanelElement() {
    return document.getElementById('dealInvestorSidepanel');
  }

  // Matched on href, not position, so the tabs can be reordered freely.
  // The pane is a lazy turbo-frame: revealing it triggers the load.
  openPanelTab(paneId) {
    const tab = this.sidepanelElement?.querySelector(`a[href="#${paneId}"]`);
    if (tab) tab.click();
  }

  // Absent when the user may not create this record for the owner — nothing to open.
  clickNewRecordLink(paneId, frameId) {
    const link = this.sidepanelElement?.querySelector(`#${paneId} a[data-turbo-frame="${frameId}"]`);
    if (link) link.click();
  }

  // "Add Investor" link handler. Follows the same reset/fetch/show sequence as
  // showSidepanel() rather than calling it directly, since this uses the link's
  // own href (an add-investor form URL) instead of a `/deal_investors/:id` URL.
  addInvestor(event) {
    event.preventDefault();
    const url = event.currentTarget.href;
    const sidepanelElement = document.getElementById('dealInvestorSidepanel');
    if (!sidepanelElement) return;

    this.resetSidepanelState();
    this.cleanupSidepanelListeners();

    const sidepanel = bootstrap.Offcanvas.getOrCreateInstance(sidepanelElement);
    const container = this.resetSidepanelFrame();
    if (!container) return;

    const frameUrl = `${url}${url.includes('?') ? '&' : '?'}_=${Date.now()}`;
    this.loadSidepanelContent(frameUrl, () => {
      requestAnimationFrame(() => {
        sidepanel.show();
      });
    });
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

  // Used by the outside-click handler in connect() to tell a genuine grid
  // cell/row/header interaction apart from a click that merely landed inside the
  // grid's DOM subtree (e.g. a scrollbar or an empty area), so highlight-clearing
  // only skips real interactions.
  isTargetInsideGridInteraction(target) {
    const gridElement = this.getGridElement();
    if (!gridElement || !target) return false;

    const element = target instanceof Element ? target : target.parentElement;
    if (!element) return false;

    const interactiveSelector = '.ag-cell, .ag-row, .ag-header-cell';
    const interactiveElement = element.closest(interactiveSelector);

    return !!interactiveElement && gridElement.contains(interactiveElement);
  }

  // AG Grid's cell-focus/range-selection styling persists a blue highlight on the
  // last-interacted cell/row even with suppressCellFocus/suppressRangeSelection
  // set (see the gridOptions comment near where those are configured), so on top
  // of the API calls this also strips the relevant classes/inline vars by hand.
  // Run on grid ready, on any click outside a real grid interaction, and whenever
  // the investor sidepanel closes, so the highlight never lingers after those events.
  clearGridHighlight() {
    const gridElement = this.getGridElement();
    const activeElement = document.activeElement;

    if (activeElement && gridElement?.contains(activeElement)) {
      activeElement.blur();
    }

    const api = this.gridOptions?.api;

    try {
      if (typeof api?.clearFocusedCell === 'function') api.clearFocusedCell();
    } catch (error) {
      console.warn('Unable to clear AG Grid focused cell', error);
    }

    try {
      if (typeof api?.clearRangeSelection === 'function') api.clearRangeSelection();
    } catch (error) {
      console.warn('Unable to clear AG Grid range selection', error);
    }

    if (!gridElement) return;

    requestAnimationFrame(() => {
      gridElement.querySelectorAll('.ag-cell-focus, .ag-cell-selected, .ag-row-selected, .ag-row-focus, .ag-cell-range-selected, .ag-cell-range-selected-1, .ag-cell-range-single-cell').forEach((element) => {
        element.classList.remove('ag-cell-focus', 'ag-cell-selected', 'ag-row-selected', 'ag-row-focus', 'ag-cell-range-selected', 'ag-cell-range-selected-1', 'ag-cell-range-single-cell');
      });

      gridElement.querySelectorAll('.ag-row').forEach((row) => {
        row.classList.remove('ag-row-selected', 'ag-row-focus', 'ag-row-hovered');
        row.style.removeProperty('--ag-selected-row-background-color');
        row.style.removeProperty('background-color');
      });

      gridElement.querySelectorAll('.ag-cell').forEach((cell) => {
        cell.classList.remove('ag-cell-focus', 'ag-cell-selected', 'ag-cell-range-selected', 'ag-cell-range-selected-1', 'ag-cell-range-single-cell');
        cell.style.removeProperty('--ag-selected-row-background-color');
        cell.style.removeProperty('background-color');
      });

      gridElement.style.removeProperty('--ag-selected-row-background-color');
      gridElement.style.removeProperty('--ag-range-selection-background-color');
      gridElement.style.removeProperty('--ag-row-hover-color');
    });
  }

  gridReady() {
    console.log("Deals List AG Grid Ready with Enhanced Features");
    this.clearGridHighlight();
    this.initTooltips();
    this.setupActivityMenu();
    this.setupRowActionsMenu();
    this.updateFilterVisuals();

    // Second half of the "New Task" / "New Note" flow: openPanelWithPendingAction()
    // reveals the tab, which starts its lazy frame loading, and this pops that
    // tab's "new" form once the frame has rendered.
    this._frameLoadHandler = (e) => {
      const action = this._pendingPanelAction;
      if (!action) return;
      // The deal-level details section has a "tasks_frame" too — ignore it.
      if (!this.sidepanelElement?.contains(e.target)) return;
      if (e.target.id !== action.tabFrameId) return;

      this._pendingPanelAction = null;
      clearTimeout(this._pendingPanelActionTimer);
      this.clickNewRecordLink(action.paneId, action.newRecordFrameId);
    };
    document.addEventListener('turbo:frame-load', this._frameLoadHandler);

    // Belt-and-braces for clearGridHighlight(): AG Grid's own focus/selection
    // events don't reliably fire for every way a cell can lose "highlighted"
    // status (e.g. clicking a button rendered inside a cell), so this also
    // clears the highlight on any click/tap that lands outside a real grid
    // interaction. Registered in the capture phase (the `true` argument) so it
    // runs before the target's own click handler can stop propagation.
    this._outsideGridClickHandler = (event) => {
      const gridElement = this.getGridElement();
      const target = event.target;

      if (!gridElement) return;

      if (!this.isTargetInsideGridInteraction(target)) {
        requestAnimationFrame(() => this.clearGridHighlight());
      }
    };
    document.addEventListener('click', this._outsideGridClickHandler, true);
    document.addEventListener('pointerup', this._outsideGridClickHandler, true);
    document.addEventListener('touchend', this._outsideGridClickHandler, true);

    // Listen for chart point clicks dispatched by charts_handler.js via the global
    // Highcharts event. No timing/polling needed — the handler fires on any click.
    this._chartFilterHandler = (e) => this.filterByChart(e.detail.type, e.detail.value);
    document.addEventListener('chart:grid-filter', this._chartFilterHandler);

    // Close the sidepanel when navigating away from this page, so it doesn't persist across Turbo visits.
    this._beforeVisitHandler = () => this.closeSidepanel();
    document.addEventListener('turbo:before-visit', this._beforeVisitHandler);

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
    // Timers hold a reference to this controller and would fire against a grid
    // api that no longer exists after a Turbo navigation.
    clearTimeout(this._quickSearchTimer);
    clearTimeout(this._pendingPanelActionTimer);

    // Bootstrap tooltips attach their own DOM elements/listeners independent of
    // this controller's element; without disposing them here they'd leak (and
    // their popper elements would keep floating on screen) across Turbo navigations.
    if (this._tooltips) {
      this._tooltips.forEach((tooltip) => tooltip.dispose());
      this._tooltips.clear();
    }

    if (this._rowActionsClickHandler) {
      document.removeEventListener('click', this._rowActionsClickHandler);
      this._rowActionsClickHandler = null;
    }

    if (this._frameLoadHandler) {
      document.removeEventListener('turbo:frame-load', this._frameLoadHandler);
      this._frameLoadHandler = null;
    }

    if (this._outsideGridClickHandler) {
      document.removeEventListener('click', this._outsideGridClickHandler, true);
      document.removeEventListener('pointerup', this._outsideGridClickHandler, true);
      document.removeEventListener('touchend', this._outsideGridClickHandler, true);
      this._outsideGridClickHandler = null;
    }

    //Clean the listeners to be recreated on new page loads, which removes stale listeners from the page
    if (this._activityMenuClickHandler) {
      document.removeEventListener('click', this._activityMenuClickHandler);
      this._activityMenuClickHandler = null;
    }

    if (this._chartFilterHandler) {
      document.removeEventListener('chart:grid-filter', this._chartFilterHandler);
    }

    // Remove the turbo:before-visit listener to avoid closing the sidepanel on future visits
    if (this._beforeVisitHandler) {
      document.removeEventListener('turbo:before-visit', this._beforeVisitHandler);
      this._beforeVisitHandler = null;
    }

    this.cleanupSidepanelListeners();

    super.disconnect();
  }

  // Build a single floating menu appended to document.body so it is never clipped
  // by AG Grid's overflow:hidden cells or the horizontal-scroll viewport.
  setupActivityMenu() {
    // Rebuilt, never reused: this menu lives on document.body, so Turbo snapshots
    // it into the page cache and a restoration visit (back button) restores the
    // markup as inert clones with none of the listeners attached below.
    document.getElementById('deals-activity-floating-menu')?.remove();

    const menu = document.createElement('div');
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

    // Delegate: open menu when any .activity-badge is clicked
    if (this._activityMenuClickHandler) return;

    this._activityMenuClickHandler = (e) => {
      const badge = e.target.closest('.activity-badge');

      if (badge) {
        e.stopPropagation();
        const id = parseInt(badge.dataset.activityId);
        const backTo = encodeURIComponent(window.location.href);
        const canUpdate = badge.dataset.canUpdate === 'true';

        if (!canUpdate) this.showAccessDenied();

        menu.dataset.activityId = id;
        this._activityMenuCanUpdate = canUpdate;
        menu.querySelector('#deals-activity-menu-show').href = `/deal_activities/${id}`;
        const entityId = badge.dataset.entityId;
        const dealInvestorId = badge.dataset.dealInvestorId;
        const activityName = badge.dataset.activityName || '';
        // Upload doc owner is DealInvestor; name preset to the deal activity title
        menu.querySelector('#deals-activity-menu-docs').href = `/documents/new?document[owner_id]=${dealInvestorId}&document[owner_type]=DealInvestor&document[entity_id]=${entityId}&document[name]=${activityName}&back_to=${backTo}`;

        menu.querySelectorAll('[data-status]').forEach(btn => {
          btn.style.display = canUpdate ? '' : 'none';
        });
        const divider = menu.querySelector('.dropdown-divider');
        if (divider) divider.style.display = canUpdate ? '' : 'none';

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
    };

    document.addEventListener('click', this._activityMenuClickHandler);
  }

  // Per-row View / Edit / Add Note / Add Task menu. Appended to document.body for
  // the same reason as the activity menu: a dropdown rendered inside a cell is
  // clipped by AG Grid's overflow:hidden viewport, and row transforms break
  // position:fixed.
  setupRowActionsMenu() {
    const MENU_WIDTH = 170;
    // One menu for the whole grid — the clicked row's id is stashed on it instead
    // of building a menu per row. Rebuilt, never reused: this menu lives on
    // document.body, so Turbo snapshots it into the page cache and a restoration
    // visit (back button) restores the markup as inert clones with none of the
    // listeners attached below.
    document.getElementById('deals-row-actions-menu')?.remove();

    const menu = document.createElement('div');
    menu.id = 'deals-row-actions-menu';
    menu.className = 'dropdown-menu shadow-sm show';
    menu.style.cssText = `position:fixed;z-index:99999;display:none;min-width:${MENU_WIDTH}px;`;
    menu.innerHTML = `
      <button class="dropdown-item" type="button" data-row-action="view">
        <i class="ti ti-eye me-2"></i>View
      </button>
      <button class="dropdown-item" type="button" data-row-action="edit">
        <i class="ti ti-pencil me-2"></i>Edit
      </button>
      <button class="dropdown-item" type="button" data-row-action="new_note">
        <i class="ti ti-notes me-2"></i>Add Note
      </button>
      <button class="dropdown-item" type="button" data-row-action="new_task">
        <i class="ti ti-plus me-2"></i>Add Task
      </button>
    `;
    document.body.appendChild(menu);

    menu.querySelectorAll('[data-row-action]').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        this.closeRowActionsMenu(menu);
        const id = menu.dataset.dealInvestorId;
        if (!id) return;

        switch (btn.dataset.rowAction) {
          case 'view': this.viewInvestor(id); break;
          case 'edit': this.editInvestor(id); break;
          case 'new_task': this.newTaskForInvestor(id); break;
          case 'new_note': this.newNoteForInvestor(id); break;
        }
      });
    });

    if (this._rowActionsClickHandler) return;

    // Delegated: AG Grid virtualises rows, so the carets come and go as you
    // scroll and cannot each hold their own listener. This one also closes the
    // menu on any outside click.
    this._rowActionsClickHandler = (e) => {
      const trigger = e.target.closest('.deals-row-actions');

      if (trigger) {
        e.preventDefault();
        e.stopPropagation();

        // Queried from the document rather than remembered: AG Grid virtualises
        // rows, so the caret that was open may already have been recycled away.
        document.querySelectorAll('.deals-row-actions--open')
                .forEach(el => el.classList.remove('deals-row-actions--open'));
        trigger.classList.add('deals-row-actions--open');

        menu.dataset.dealInvestorId = trigger.dataset.id;
        // Editing is gated by the same policy the row JSON reports.
        menu.querySelector('[data-row-action="edit"]').style.display =
          trigger.dataset.canUpdate === 'true' ? '' : 'none';

        const rect = trigger.getBoundingClientRect();
        // Shown before measuring: a display:none element has no offsetHeight, and
        // the height varies with how many items the row's policies leave visible.
        menu.style.display = 'block';
        const menuHeight = menu.offsetHeight;

        let left = rect.right - MENU_WIDTH;
        let top = rect.bottom + 4;

        if (left < 8) left = 8;
        // Flip above the caret when it would otherwise run off the bottom.
        if (top + menuHeight > window.innerHeight) top = rect.top - menuHeight - 4;
        if (top < 8) top = 8;

        menu.style.left = `${left}px`;
        menu.style.top = `${top}px`;
        return;
      }

      if (!menu.contains(e.target)) {
        this.closeRowActionsMenu(menu);
      }
    };

    document.addEventListener('click', this._rowActionsClickHandler);
  }

  // ensure the dropdown button is not left in the "open" state when the menu is closed by clicking outside
  closeRowActionsMenu(menu) {
    menu.style.display = 'none';
    document.querySelectorAll('.deals-row-actions--open')
            .forEach(el => el.classList.remove('deals-row-actions--open'));
  }

  // Called repeatedly as the grid re-renders (scroll, column changes, first
  // render) since AG Grid recycles/recreates cell DOM nodes, which would
  // otherwise leave old Tooltip instances pointing at detached elements. Any
  // existing instance on a trigger is disposed before creating a new one so
  // re-renders don't stack duplicate tooltips on the same element; instances
  // are tracked in this._tooltips so disconnect() can dispose whatever's left.
  initTooltips() {
    const tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));

    if (!this._tooltips) {
      this._tooltips = new Set();
    }

    tooltipTriggerList.forEach((tooltipTriggerEl) => {
      const existingTooltip = bootstrap.Tooltip.getInstance(tooltipTriggerEl);
      if (existingTooltip) {
        existingTooltip.dispose();
        this._tooltips.delete(existingTooltip);
      }

      const title = tooltipTriggerEl.getAttribute('title');
      if (!title) return;

      const tooltip = new bootstrap.Tooltip(tooltipTriggerEl);
      this._tooltips.add(tooltip);
    });
  }

  // Client-side search over the rows already loaded — no server round-trip.
  // Debounced because setQuickFilter re-evaluates every row, which is visible
  // while typing on a large deal.
  quickSearch(event) {
    const term = event.target.value;
    clearTimeout(this._quickSearchTimer);
    this._quickSearchTimer = setTimeout(() => {
      if (!this.gridOptions?.api) return;
      this.gridOptions.api.setQuickFilter(term);
    }, 200);
  }

  // The clear "x" now lives inside the search box, so it has to reset the search
  // as well as the column filters — and cancel any debounced keystroke that
  // would otherwise re-apply the term it just cleared.
  clearFilters() {
    clearTimeout(this._quickSearchTimer);
    if (this.hasSearchTarget) this.searchTarget.value = '';
    this.gridOptions.api.setQuickFilter('');
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
