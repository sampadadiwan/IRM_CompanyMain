# Portfolio Company Agent — Dashboard Redesign (Technical Design)

## Overview

Redesign the "Portfolio Agent Reports" tab on the SupportAgent show page from a plain table into a rich dashboard with stat cards, bar chart, action buttons, and a full-width searchable company table with dynamic per-document-type columns.

**Scope:** View layer + one presenter + two Stimulus controllers. No new models or migrations.

---

## Revision History

| Date | Change | Reason |
|------|--------|--------|
| 2026-06-25 | Initial design | — |
| 2026-06-29 | v2 — Incorporate product feedback | See "Design Changes (v2)" below |
| 2026-06-29 | v2.1 — Implementation fixes | Batch progress on dashboard, AgentChartJob decoupling in generic loop, panel_id fix |
| 2026-06-30 | v2.2 — Pagination, search, send reminders | See "Design Changes (v2.2)" below |

### Design Changes (v2.2)

1. **Server-side pagination** — Pagy (10 per page) replaces the single unbounded table. Table is wrapped in a `turbo_frame_tag "portfolio_table_frame"` so pagination, filtering, and search all stay within the tab (no full page reload). Stat cards and chart remain outside the frame and always show full-dataset aggregations.
2. **Ransack-based search** — Replaced client-side Stimulus search with server-side Ransack (`investor_investor_name_cont`). Required adding a `belongs_to :investor` association on `SupportAgentReport` for the polymorphic join, plus `ransackable_associations` whitelist.
3. **Send Reminders action** — `POST /support_agents/:id/send_reminders` sends `EntityMailer.kpi_reminder` to overdue companies. Deduplicates via `last_kpi_reminder_sent_at` in `json_fields` (once per day). Pre-loads reports and investors to avoid N+1.
4. **Stat card filtering via Turbo Frames** — Stat cards are now `link_to` elements with `data-turbo-frame: "portfolio_table_frame"`, triggering server-side filtering. Auto-scrolls to table on frame load.
5. **Status dropdown via Stimulus** — Status filter dropdown uses `portfolio-dashboard-filter#statusDropdownChange` action instead of inline JavaScript.
6. **Chart.js rendering fix** — Fixed chart shrinking inside hidden Bootstrap tabs by setting explicit `position: relative; height: 280px` on the parent container div, plus a `shown.bs.tab` listener that calls `chart.resize()`.

### Design Changes (v2)

Based on product review (2026-06-26), the following changes were made:

1. **Decouple AgentChartJob from PortfolioCompanyAgent** — running the portfolio agent no longer auto-triggers chart generation. Chart Agent will be a separate, independent agent. Why: different use cases, clients may want only one, and charts slow down the compliance run.
2. **Clickable stat cards** — clicking a stat card filters the company table to that status (moved from Phase 2 to Phase 1). Why: makes stat cards interactive navigation instead of passive display.
3. **Full-width company table** — removed the 8/4 col split with sidebar. Table is now col-12. Why: more room for dynamic document columns; insights/overdue sidebars removed.
4. **Dynamic document columns** — replaced single "Documents" column with one column per `File`-type `FormCustomField` configured on the entity's KPI report form. Why: product wants per-document-type compliance visibility (e.g., "Board Minutes" vs "Financial Statement" vs "Cap Table" each as separate columns).
5. **Removed Portfolio Insights sidebar** — LLM-generated insights panel dropped. Why: product felt the data is already visible in the table; redundant.
6. **Removed Overdue Companies sidebar** — part of the full-width table change. Overdue info is visible via stat cards + table filtering.
7. **Removed KPI Charts section (Row 4)** — charts are decoupled from this agent. Why: chart generation is a separate agent; showing one agent's output on another agent's dashboard adds coupling.
8. **Document-type breakdown in bar chart** — the "Missing by Type" bar chart now shows individual document types (e.g., "Financial Statement: 8 missing") instead of a generic "Documents" bucket. Data already exists in `document_issues[].message`.

---

## Architecture

### Data Flow

```
SupportAgentReport (existing, per company)
  └── json_fields: { kpi_issues, document_issues, valuation_issues, final_status, run_at, ... }
      └── document_issues[]: { type: :missing, message: "Financial Statement", severity: :blocking }

PortfolioDashboardPresenter (NEW)
  └── Aggregates all reports → stat counts, status distribution, issues by type, per-doc-type breakdown

FormCustomField (existing)
  └── field_type: "File" entries on the entity's KPI report form → drives dynamic document columns
```

### What Changes vs. What Stays

| Component | Change Type |
|-----------|-------------|
| `_portfolio_reports_tab.html.erb` | **Rewrite** — dashboard layout, full-width table, no sidebar, no charts row |
| `_portfolio_report_detail.html.erb` | **Keep** — still used for row expansion in the company table |
| `PortfolioDashboardPresenter` | **Modify** — add `document_types`, `document_ok?`; fix `issues_by_type` to use `message` field; remove insights methods |
| `portfolio_dashboard_filter_controller.js` | **Modify** — add `filterByStatus(event)` for clickable stat cards |
| `portfolio_dashboard_chart_controller.js` | **No change** — already renders dynamic labels from presenter |
| `support_agents_controller.rb` | **Modify** — remove AgentChart loading |
| `portfolio_company_agent.rb` | **Modify** — remove `AgentChartJob` from `process_batch` block |
| `_portfolio_dashboard_stats.html.erb` | **Modify** — add click-to-filter `data-action` on each card |
| `_portfolio_dashboard_table.html.erb` | **Rewrite** — dynamic document columns, full-width, dynamic colspan |
| `_portfolio_dashboard_insights.html.erb` | **Delete** — sidebar removed |
| `_portfolio_dashboard_overdue.html.erb` | **Delete** — sidebar removed |
| `_portfolio_dashboard_kpi_charts.html.erb` | **Delete** — charts decoupled |

---

## Component Details

### 1. PortfolioDashboardPresenter

**File:** `app/packs/ai/support_agents/services/portfolio_dashboard_presenter.rb`

Takes the collection of `SupportAgentReport` records (already loaded by `AgentReportsQuery#portfolio_reports`) and computes all dashboard aggregations.

```ruby
# frozen_string_literal: true

# Computes dashboard aggregations from portfolio company agent reports.
#
# @see SupportAgentReport
# @see PortfolioCompanyAgent
class PortfolioDashboardPresenter
  attr_reader :reports, :support_agent

  # @param reports [Array<SupportAgentReport>] portfolio reports collection
  # @param support_agent [SupportAgent] the portfolio company agent record
  def initialize(reports, support_agent)
    @reports = reports.select { |r| r.json_fields.present? }
    @support_agent = support_agent
  end

  # --- Stat Cards ---

  # @return [Integer] total portfolio companies in the entity
  def total_companies
    @total_companies ||= Investor.where(
      entity_id: support_agent.entity_id,
      category: "Portfolio Company"
    ).count
  end

  # @return [Integer] companies that have at least one report
  def submissions_received
    @submissions_received ||= reports.count { |r| final_status(r).in?(%w[ready blocked]) }
  end

  # @return [Integer] companies with no blocking issues
  def fully_complete
    @fully_complete ||= reports.count { |r| final_status(r) == "ready" }
  end

  # @return [Integer] companies with no report or blocked status
  def pending_submissions
    @pending_submissions ||= total_companies - submissions_received
  end

  # @return [Integer] total blocking issues across all reports
  def total_issues
    @total_issues ||= reports.sum { |r| blocking_count(r) }
  end

  # --- Dynamic Document Types ---

  # Returns the list of File-type custom field labels configured on the entity's
  # KPI report form. These become the dynamic document columns in the table.
  #
  # Falls back to document names found in report data if no FormCustomFields exist
  # (e.g., entity uses only agent-level required_docs config).
  #
  # @return [Array<String>] document type labels (e.g., ["Financial Statement", "Board Minutes"])
  def document_types
    @document_types ||= begin
      # Primary source: File-type fields on the PortfolioKpiReport form
      form_type = FormType.find_by(entity_id: support_agent.entity_id, name: "PortfolioKpiReport")
      labels = form_type&.form_custom_fields&.where(field_type: "File")&.map(&:label) || []

      # Secondary source: agent-level required_docs config
      agent_docs = support_agent.json_fields["required_docs"].to_s.split(",").map(&:strip).reject(&:blank?)
      labels += agent_docs

      # Fallback: extract unique document names from existing report data
      if labels.empty?
        labels = reports.flat_map { |r|
          Array(r.json_fields.with_indifferent_access[:document_issues])
            .select { |i| i[:type].to_s == "missing" }
            .map { |i| i[:message].presence }
            .compact
        }.uniq
      end

      labels.uniq
    end
  end

  # --- Missing by Type (for bar chart) ---

  # Returns count of companies with blocking issues per compliance category.
  # Document types are broken out individually (e.g., "Financial Statement: 8")
  # instead of a single "Documents" bucket.
  #
  # @return [Hash{String => Integer}] issue counts per compliance category
  def issues_by_type
    @issues_by_type ||= begin
      result = { "KPI" => 0, "Valuation" => 0 }

      reports.each do |r|
        data = r.json_fields.with_indifferent_access
        kpi_issues = Array(data[:kpi_issues])
        val_issues = Array(data[:valuation_issues])
        doc_issues = Array(data[:document_issues])

        result["KPI"] += 1 if kpi_issues.any? { |i| i[:severity].to_s == "blocking" }
        result["Valuation"] += 1 if val_issues.any? { |i| i[:severity].to_s == "blocking" }

        # Count per document type — each missing doc issue has the doc name in :message
        doc_issues.select { |i| i[:severity].to_s == "blocking" || i[:type].to_s == "missing" }.each do |i|
          name = i[:message].presence || "Documents"
          result[name] ||= 0
          result[name] += 1
        end
      end

      result.reject { |_, v| v == 0 }
    end
  end

  # --- Overdue / Pending Companies ---

  # @return [Array<Hash>] overdue companies sorted by issues_count descending
  def overdue_companies
    @overdue_companies ||= reports
      .select { |r| final_status(r) == "blocked" }
      .map { |r|
        data = r.json_fields.with_indifferent_access
        run_at = Time.zone.parse(data[:run_at]) rescue nil
        {
          name: r.owner&.name || r.owner_name || "Unknown",
          owner_id: r.owner_id,
          issues_count: blocking_count(r),
          days_since_run: run_at ? ((Time.current - run_at) / 1.day).floor : nil
        }
      }
      .sort_by { |c| -(c[:issues_count]) }
  end

  # --- Per-Report Helpers (used by table rows) ---

  # @param report [SupportAgentReport]
  # @return [String] display status label
  def report_status(report)
    status = final_status(report)
    case status
    when "ready" then "Complete"
    when "blocked" then blocking_count(report) == total_possible_issues ? "Pending" : "Incomplete"
    else "Pending"
    end
  end

  # @param report [SupportAgentReport]
  # @return [String] Bootstrap color class
  def report_status_color(report)
    case report_status(report)
    when "Complete" then "success"
    when "Incomplete" then "warning"
    when "Pending" then "danger"
    else "secondary"
    end
  end

  # Checks if a broad category (KPI or Valuation) has no blocking issues.
  #
  # @param report [SupportAgentReport]
  # @param category [Symbol] :kpi or :valuation
  # @return [Boolean] true if category has no blocking issues
  def category_ok?(report, category)
    data = report.json_fields.with_indifferent_access
    issues = Array(data[:"#{category}_issues"])
    issues.none? { |i| i[:severity].to_s == "blocking" || i[:type].to_s == "missing" }
  end

  # Checks if a specific named document is present (not missing) for a report.
  # Used for the dynamic per-document-type columns in the table.
  #
  # @param report [SupportAgentReport]
  # @param doc_name [String] the document type label (e.g., "Financial Statement")
  # @return [Boolean] true if the document is NOT missing
  def document_ok?(report, doc_name)
    data = report.json_fields.with_indifferent_access
    doc_issues = Array(data[:document_issues])
    doc_issues.none? { |i|
      (i[:severity].to_s == "blocking" || i[:type].to_s == "missing") &&
        i[:message].to_s == doc_name
    }
  end

  private

  # @param report [SupportAgentReport]
  # @return [String] normalised final status
  def final_status(report)
    (report.json_fields.with_indifferent_access[:final_status].presence || report.status.to_s).downcase
  end

  # @param report [SupportAgentReport]
  # @return [Integer] total blocking issues in this report
  def blocking_count(report)
    data = report.json_fields.with_indifferent_access
    kpi_blocking = Array(data[:kpi_issues]).count { |i| i[:severity].to_s == "blocking" }
    doc_blocking = Array(data[:document_issues]).count { |i| i[:severity].to_s == "blocking" || i[:type].to_s == "missing" }
    val_blocking = Array(data[:valuation_issues]).count { |i| i[:severity].to_s == "blocking" }
    kpi_blocking + doc_blocking + val_blocking
  end

  # Dynamic count: KPI + Valuation + number of configured document types
  #
  # @return [Integer] minimum possible issue categories
  def total_possible_issues
    2 + [document_types.size, 1].max
  end
end
```

**Why a presenter instead of helper methods:** The aggregation logic is non-trivial (iterating reports, grouping by type, counting severities). A presenter keeps the view clean and is testable in isolation. It takes the same `@portfolio_reports` already loaded by the controller — no new DB queries for stat cards or charts.

**Key changes from v1:**
- `document_types` method — queries `FormCustomField` for `File`-type fields on the entity's KPI report form. Returns labels that become dynamic table columns.
- `document_ok?(report, doc_name)` — checks if a specific named document is missing for a report. Used per-cell in the dynamic columns.
- `issues_by_type` — fixed to use `i[:message]` (not `i[:document_name]`) for per-document breakdown. Each document type now appears as its own bar in the chart.
- `total_possible_issues` — now dynamic: `2 + document_types.size` instead of hardcoded `3`.
- Removed `portfolio_insights` and `insights_generated_at` methods (insights sidebar dropped).

---

### 2. Controller Changes

**File:** `app/packs/ai/support_agents/controllers/support_agents_controller.rb`

In the `show` action, after loading `@portfolio_reports`, instantiate the presenter:

```ruby
# Inside the show action, after loading @portfolio_reports:
if @support_agent.agent_type == "PortfolioCompanyAgent"
  @portfolio_presenter = PortfolioDashboardPresenter.new(@portfolio_reports, @support_agent)
end
```

**Change from v1:** Removed `@portfolio_agent_charts` loading — charts are decoupled from this agent.

---

### 3. View Structure (Partials)

**File:** `app/packs/ai/support_agents/views/support_agents/_portfolio_reports_tab.html.erb`

Dashboard container — simplified layout with no sidebar and no charts row:

```erb
<% if portfolio_reports.empty? %>
  <div class="alert alert-secondary">
    <i class="ti ti-info-circle"></i> No portfolio reports yet. Run the agent on schedule to generate reports.
  </div>
<% else %>
  <% presenter = local_assigns[:portfolio_presenter] || PortfolioDashboardPresenter.new(portfolio_reports, support_agent) %>

  <div class="portfolio-dashboard" data-controller="portfolio-dashboard-filter">
    <%= turbo_stream_from "batch_progress_#{support_agent.id}" %>

    <%# Row 1: Stat Cards (clickable — filter the table) %>
    <%= render "portfolio_dashboard_stats", presenter: presenter %>

    <%# Row 2: Bar Chart + Actions %>
    <div class="row g-4 mb-4">
      <div class="col-md-6">
        <%= render "portfolio_dashboard_chart", presenter: presenter %>
      </div>
      <div class="col-md-6">
        <%= render "portfolio_dashboard_actions",
                    support_agent: support_agent,
                    presenter: presenter %>
      </div>
    </div>

    <%# Row 3: Full-width Company Table (dynamic document columns) %>
    <div class="mb-4">
      <%= render "portfolio_dashboard_table",
                  portfolio_reports: portfolio_reports,
                  presenter: presenter,
                  support_agent: support_agent %>
    </div>

    <%# Footer: Recommended Next Steps %>
    <%= render "portfolio_dashboard_footer",
                presenter: presenter,
                support_agent: support_agent,
                portfolio_reports: portfolio_reports %>
  </div>
<% end %>
```

**Changes from v1:**
- Row 3 is now full-width (`div` instead of `row > col-md-8 + col-md-4`). No sidebar.
- Removed `_portfolio_dashboard_insights` render (deleted).
- Removed `_portfolio_dashboard_overdue` render (deleted).
- Removed Row 4 `_portfolio_dashboard_kpi_charts` render (deleted).
- `data-controller="portfolio-dashboard-filter"` on wrapper div — allows stat cards and table to share one Stimulus filter controller.
- `turbo_stream_from` subscription — receives batch progress broadcasts on the portfolio tab.

#### Batch Progress on the Dashboard (v2.1)

"Run Validation" stays on the portfolio tab and shows a live progress panel below the button.

**How it works:**
1. `_portfolio_dashboard_actions.html.erb` contains the Run Validation `button_to` (Turbo-enabled, no `data-turbo: false`) and a `#portfolio_batch_progress_panel` div below it.
2. Controller `run_with_steps` responds with Turbo Stream replacing both `batch_progress_panel` (General tab) and `portfolio_batch_progress_panel` (Portfolio tab).
3. `_batch_progress_panel.html.erb` accepts an optional `panel_id` local — renders `id="<%= panel_id || 'batch_progress_panel' %>"` so each panel keeps its own DOM ID across replacements.
4. `SupportAgentService.broadcast_batch_progress` and `.broadcast_batch_complete` broadcast to both panel IDs, passing `panel_id: target` in locals so the partial preserves the correct ID.
5. `turbo_stream_from` on the portfolio tab receives the broadcasts and Turbo replaces the matching `#portfolio_batch_progress_panel` in-place.

#### Partial: `_portfolio_dashboard_stats.html.erb`

Five Bootstrap cards with click-to-filter. Each card is wrapped in a link-like element that triggers the Stimulus filter controller on the table. The filter controller is on the table partial, so stat cards use `data-action` with a global dispatch pattern — they emit a custom event that the filter controller listens for.

**Implementation approach:** Stat cards use `data-action="click->portfolio-dashboard-filter#filterByStatus"` with `data-portfolio-dashboard-filter-status-param`. Since the filter controller lives on the table's DOM (not the stat cards), we use Stimulus `outlets` or a simpler approach: the entire dashboard div gets the filter controller, and both stat cards and table are inside it.

```erb
<div class="row g-3 mb-4">
  <%# Card: Total Companies %>
  <div class="col">
    <div class="card border-0 shadow-sm h-100 cursor-pointer"
         role="button"
         data-action="click->portfolio-dashboard-filter#filterByStatus"
         data-portfolio-dashboard-filter-status-param="">
      <div class="card-body">
        <div class="d-flex align-items-center justify-content-between mb-2">
          <small class="text-muted">Total Companies</small>
          <span class="text-primary"><i class="ti ti-building fs-4"></i></span>
        </div>
        <h2 class="mb-0 fw-bold"><%= presenter.total_companies %></h2>
        <small class="text-muted">In portfolio</small>
      </div>
    </div>
  </div>

  <%# Card: Submissions Received %>
  <div class="col">
    <div class="card border-0 shadow-sm h-100 cursor-pointer"
         role="button"
         data-action="click->portfolio-dashboard-filter#filterByStatus"
         data-portfolio-dashboard-filter-status-param="submitted">
      <div class="card-body">
        <div class="d-flex align-items-center justify-content-between mb-2">
          <small class="text-muted">Submissions Received</small>
          <span class="text-info"><i class="ti ti-file-check fs-4"></i></span>
        </div>
        <h2 class="mb-0 fw-bold"><%= presenter.submissions_received %></h2>
        <% pct = presenter.total_companies > 0 ? (presenter.submissions_received * 100.0 / presenter.total_companies).round(1) : 0 %>
        <small class="text-muted"><%= pct %>% of total</small>
        <div class="progress mt-2" style="height: 4px;">
          <div class="progress-bar bg-info" style="width: <%= pct %>%"></div>
        </div>
      </div>
    </div>
  </div>

  <%# Card: Fully Complete %>
  <div class="col">
    <div class="card border-0 shadow-sm h-100 cursor-pointer"
         role="button"
         data-action="click->portfolio-dashboard-filter#filterByStatus"
         data-portfolio-dashboard-filter-status-param="Complete">
      <div class="card-body">
        <div class="d-flex align-items-center justify-content-between mb-2">
          <small class="text-muted">Fully Complete</small>
          <span class="text-success"><i class="ti ti-circle-check fs-4"></i></span>
        </div>
        <h2 class="mb-0 fw-bold"><%= presenter.fully_complete %></h2>
        <% pct = presenter.total_companies > 0 ? (presenter.fully_complete * 100.0 / presenter.total_companies).round(1) : 0 %>
        <small class="text-muted"><%= pct %>% of total</small>
        <div class="progress mt-2" style="height: 4px;">
          <div class="progress-bar bg-success" style="width: <%= pct %>%"></div>
        </div>
      </div>
    </div>
  </div>

  <%# Card: Pending Submissions %>
  <div class="col">
    <div class="card border-0 shadow-sm h-100 cursor-pointer"
         role="button"
         data-action="click->portfolio-dashboard-filter#filterByStatus"
         data-portfolio-dashboard-filter-status-param="Pending">
      <div class="card-body">
        <div class="d-flex align-items-center justify-content-between mb-2">
          <small class="text-muted">Pending Submissions</small>
          <span class="text-danger"><i class="ti ti-clock-exclamation fs-4"></i></span>
        </div>
        <h2 class="mb-0 fw-bold"><%= presenter.pending_submissions %></h2>
        <% pct = presenter.total_companies > 0 ? (presenter.pending_submissions * 100.0 / presenter.total_companies).round(1) : 0 %>
        <small class="text-muted"><%= pct %>% of total</small>
        <div class="progress mt-2" style="height: 4px;">
          <div class="progress-bar bg-danger" style="width: <%= pct %>%"></div>
        </div>
      </div>
    </div>
  </div>

  <%# Card: Total Issues %>
  <div class="col">
    <div class="card border-0 shadow-sm h-100 cursor-pointer"
         role="button"
         data-action="click->portfolio-dashboard-filter#filterByStatus"
         data-portfolio-dashboard-filter-status-param="issues">
      <div class="card-body">
        <div class="d-flex align-items-center justify-content-between mb-2">
          <small class="text-muted">Total Issues</small>
          <span class="text-warning"><i class="ti ti-alert-triangle fs-4"></i></span>
        </div>
        <h2 class="mb-0 fw-bold"><%= presenter.total_issues %></h2>
        <small class="text-muted">Across all companies</small>
      </div>
    </div>
  </div>
</div>
```

**Design note on clickable cards:** Each card passes a `status-param` to the filter controller:
- "Total Companies" → `""` (empty = show all, resets filter)
- "Submissions Received" → `"submitted"` (Complete + Incomplete, i.e., anyone with a report)
- "Fully Complete" → `"Complete"`
- "Pending Submissions" → `"Pending"`
- "Total Issues" → `"issues"` (any company with issues > 0)

The filter controller's `filterByStatus` method sets the dropdown and calls `filter()`. For special values like `"submitted"` and `"issues"`, it applies custom logic (see Stimulus controller section below).

**Stimulus controller scope:** To allow stat cards (outside the table partial) to reach the filter controller (inside the table partial), the `data-controller="portfolio-dashboard-filter"` must be moved UP to the `_portfolio_reports_tab.html.erb` wrapper `div.portfolio-dashboard`, not on the table card. The table partial then uses targets only (no controller declaration).

#### Partial: `_portfolio_dashboard_chart.html.erb`

No change from v1 — the bar chart already renders dynamic labels from `presenter.issues_by_type`. The fix is in the presenter (using `i[:message]` instead of `i[:document_name]`), not in the partial.

#### Partial: `_portfolio_dashboard_actions.html.erb`

No change from v1. Action buttons + pending companies list remain.

#### Partial: `_portfolio_dashboard_table.html.erb`

Full-width company table with dynamic per-document-type columns.

```erb
<div class="card border-0 shadow-sm">
  <div class="card-body">
    <%# Table Header with Search + Filter %>
    <div class="d-flex align-items-center justify-content-between mb-3">
      <h6 class="fw-bold mb-0">Company Wise Status</h6>
      <div class="d-flex gap-2">
        <select class="form-select form-select-sm" style="width: 150px;"
                data-portfolio-dashboard-filter-target="statusFilter"
                data-action="change->portfolio-dashboard-filter#filter">
          <option value="">All Statuses</option>
          <option value="Complete">Complete</option>
          <option value="Incomplete">Incomplete</option>
          <option value="Pending">Pending</option>
        </select>
        <div class="input-group input-group-sm" style="width: 200px;">
          <span class="input-group-text"><i class="ti ti-search"></i></span>
          <input type="text" class="form-control" placeholder="Search company..."
                 data-portfolio-dashboard-filter-target="search"
                 data-action="input->portfolio-dashboard-filter#filter">
        </div>
      </div>
    </div>

    <% doc_types = presenter.document_types %>
    <% col_count = 6 + doc_types.size %>
    <%# 6 fixed columns: Company Name, Status, KPI, Valuation, Issues, Last Updated, Actions = 7 + doc_types %>
    <% col_count = 7 + doc_types.size %>

    <%# Table %>
    <div class="table-responsive">
      <table class="table table-hover align-middle mb-0">
        <thead class="table-light">
          <tr>
            <th>Company Name</th>
            <th>Status</th>
            <th class="text-center">KPI</th>
            <th class="text-center">Valuation</th>
            <% doc_types.each do |doc_type| %>
              <th class="text-center"><%= doc_type %></th>
            <% end %>
            <th class="text-center">Issues</th>
            <th>Last Updated</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody data-portfolio-dashboard-filter-target="tableBody">
          <% portfolio_reports.each do |report| %>
            <% data = (report.json_fields || {}).with_indifferent_access %>
            <% status = presenter.report_status(report) %>
            <% color = presenter.report_status_color(report) %>
            <tr data-status="<%= status %>"
                data-company="<%= (report.owner&.name || report.owner_name || '').downcase %>"
                data-issues="<%= Array(data[:kpi_issues]).count { |i| i[:severity].to_s == 'blocking' } +
                                  Array(data[:document_issues]).count { |i| i[:severity].to_s == 'blocking' || i[:type].to_s == 'missing' } +
                                  Array(data[:valuation_issues]).count { |i| i[:severity].to_s == 'blocking' } %>">
              <td>
                <strong><%= report.owner&.name || report.owner_name || "N/A" %></strong>
              </td>
              <td>
                <span class="badge bg-<%= color %>"><%= status %></span>
              </td>
              <td class="text-center">
                <% if presenter.category_ok?(report, :kpi) %>
                  <i class="ti ti-check text-success fs-5"></i>
                <% else %>
                  <i class="ti ti-x text-danger fs-5"></i>
                <% end %>
              </td>
              <td class="text-center">
                <% if presenter.category_ok?(report, :valuation) %>
                  <i class="ti ti-check text-success fs-5"></i>
                <% else %>
                  <i class="ti ti-x text-danger fs-5"></i>
                <% end %>
              </td>
              <% doc_types.each do |doc_type| %>
                <td class="text-center">
                  <% if presenter.document_ok?(report, doc_type) %>
                    <i class="ti ti-check text-success fs-5"></i>
                  <% else %>
                    <i class="ti ti-x text-danger fs-5"></i>
                  <% end %>
                </td>
              <% end %>
              <td class="text-center">
                <% count = Array(data[:kpi_issues]).count { |i| i[:severity].to_s == "blocking" } +
                           Array(data[:document_issues]).count { |i| i[:severity].to_s == "blocking" || i[:type].to_s == "missing" } +
                           Array(data[:valuation_issues]).count { |i| i[:severity].to_s == "blocking" } %>
                <% if count > 0 %>
                  <span class="text-danger fw-bold"><%= count %></span>
                <% else %>
                  <span class="text-success">0</span>
                <% end %>
              </td>
              <td>
                <% if data[:run_at].present? %>
                  <% run_at = Time.zone.parse(data[:run_at]) rescue nil %>
                  <small><%= run_at&.strftime("%b %d, %Y") || "--" %></small>
                <% else %>
                  <small>--</small>
                <% end %>
              </td>
              <td>
                <div class="btn-group btn-group-sm">
                  <button type="button" class="btn btn-outline-secondary"
                          data-bs-toggle="collapse"
                          data-bs-target="#report-detail-<%= report.id %>"
                          title="View Details">
                    <i class="ti ti-eye"></i>
                  </button>
                  <% if report.owner_id.present? %>
                    <%= link_to investor_path(report.owner_id),
                          class: "btn btn-outline-secondary",
                          title: "View Company",
                          data: { turbo: false } do %>
                      <i class="ti ti-external-link"></i>
                    <% end %>
                  <% end %>
                </div>
              </td>
            </tr>
            <%# Expandable detail row — reuses existing partial %>
            <tr class="collapse" id="report-detail-<%= report.id %>">
              <td colspan="<%= col_count %>" class="bg-light p-3">
                <%= render 'portfolio_report_detail', report: report, data: data %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  </div>
</div>
```

**Key changes from v1:**
- Single "Documents" column replaced with `<% doc_types.each %>` loop generating one `<th>` + `<td>` per document type.
- Uses `presenter.document_ok?(report, doc_type)` per cell instead of `presenter.category_ok?(report, :document)`.
- `colspan` on detail row is dynamic: `7 + doc_types.size` (Company, Status, KPI, Valuation, [doc columns...], Issues, Last Updated, Actions).
- Each `<tr>` has `data-issues` attribute for the "Total Issues" stat card filter.
- `data-controller` removed from this partial — moved to the parent `div.portfolio-dashboard` in `_portfolio_reports_tab.html.erb`.

#### Partial: `_portfolio_dashboard_footer.html.erb`

No change from v1. Recommended next steps + last run info.

#### Deleted Partials

| Partial | Reason |
|---------|--------|
| `_portfolio_dashboard_insights.html.erb` | Insights sidebar removed per product feedback |
| `_portfolio_dashboard_overdue.html.erb` | Overdue sidebar removed; info accessible via stat card filter |
| `_portfolio_dashboard_kpi_charts.html.erb` | Charts decoupled from this agent |

---

### 4. Stimulus Controllers

#### `portfolio_dashboard_chart_controller.js`

No change from v1. The bar chart already renders whatever labels/values the presenter provides. The per-document-type breakdown is handled by the presenter fix.

#### `portfolio_dashboard_filter_controller.js`

Updated to support clickable stat cards via `filterByStatus` method.

**File:** `app/javascript/controllers/portfolio_dashboard_filter_controller.js`

```javascript
import { Controller } from "@hotwired/stimulus"

// Provides client-side search, status filtering, and stat card click-to-filter
// for the portfolio dashboard company table.
export default class extends Controller {
  static targets = ["search", "statusFilter", "tableBody"]

  filter() {
    const query = this.hasSearchTarget ? this.searchTarget.value.toLowerCase() : ""
    const status = this.hasStatusFilterTarget ? this.statusFilterTarget.value : ""
    const rows = this.tableBodyTarget.querySelectorAll("tr[data-status]")

    rows.forEach(row => {
      const detailRow = row.nextElementSibling
      const matchesSearch = !query || row.dataset.company.includes(query)
      const matchesStatus = !status || row.dataset.status === status
      const visible = matchesSearch && matchesStatus

      row.style.display = visible ? "" : "none"
      if (detailRow && detailRow.classList.contains("collapse")) {
        detailRow.style.display = visible ? "" : "none"
      }
    })
  }

  // Called by stat card clicks. Handles standard statuses and special filters.
  filterByStatus(event) {
    const status = event.params.status

    if (status === "submitted") {
      // "Submissions Received" = Complete + Incomplete (anyone with a report)
      if (this.hasStatusFilterTarget) this.statusFilterTarget.value = ""
      this._filterCustom(row => row.dataset.status === "Complete" || row.dataset.status === "Incomplete")
      return
    }

    if (status === "issues") {
      // "Total Issues" = any company with issues > 0
      if (this.hasStatusFilterTarget) this.statusFilterTarget.value = ""
      this._filterCustom(row => parseInt(row.dataset.issues || "0", 10) > 0)
      return
    }

    // Standard status filter (Complete, Incomplete, Pending) or empty string (show all)
    if (this.hasStatusFilterTarget) this.statusFilterTarget.value = status
    this.filter()
  }

  filterPending() {
    if (this.hasStatusFilterTarget) this.statusFilterTarget.value = "Incomplete"
    this.filter()
  }

  // Applies a custom row-level predicate for non-standard filters.
  _filterCustom(predicate) {
    const query = this.hasSearchTarget ? this.searchTarget.value.toLowerCase() : ""
    const rows = this.tableBodyTarget.querySelectorAll("tr[data-status]")

    rows.forEach(row => {
      const detailRow = row.nextElementSibling
      const matchesSearch = !query || row.dataset.company.includes(query)
      const matchesPredicate = predicate(row)
      const visible = matchesSearch && matchesPredicate

      row.style.display = visible ? "" : "none"
      if (detailRow && detailRow.classList.contains("collapse")) {
        detailRow.style.display = visible ? "" : "none"
      }
    })
  }
}
```

**Key changes from v1:**
- `filterByStatus(event)` — new method called by stat card clicks. Reads `event.params.status` (Stimulus params from `data-portfolio-dashboard-filter-status-param`).
- Handles special values: `"submitted"` (Complete + Incomplete) and `"issues"` (issues > 0).
- `_filterCustom(predicate)` — private helper for non-standard row filtering.
- Added `hasSearchTarget` / `hasStatusFilterTarget` guards so stat card clicks work even when the controller is scoped above the table.

**Stimulus controller scope change:** The `data-controller="portfolio-dashboard-filter"` declaration moves from the table card div to the parent `div.portfolio-dashboard` in `_portfolio_reports_tab.html.erb`. This allows stat cards (Row 1) and action buttons (Row 2) to trigger filter methods on the same controller instance that owns the table targets (Row 3).

Updated `_portfolio_reports_tab.html.erb` wrapper:

```erb
<div class="portfolio-dashboard" data-controller="portfolio-dashboard-filter">
```

---

### 5. Decouple AgentChartJob from PortfolioCompanyAgent

**File:** `app/packs/ai/support_agents/services/portfolio_company_agent.rb`

Remove the `AgentChartJob.perform_later` call from the `process_batch` block:

```ruby
# BEFORE (v1):
def self.process_batch(support_agent_id:, targets:, user_id:, entity_id:, with_steps: false, execution_mode: :adhoc_batch)
  targets = targets.includes(:portfolio_kpi_reports, :documents, :valuations) if targets.respond_to?(:includes)

  run_batch(
    support_agent_id: support_agent_id,
    targets: targets,
    user_id: user_id,
    entity_id: entity_id,
    execution_mode: execution_mode
  ) do |successes|
    if successes.any?
      processed_ids = successes.pluck(:id)
      AgentChartJob.perform_later(user_id, portfolio_company_ids: processed_ids.uniq, execution_mode: execution_mode)
    end
  end
end

# AFTER (v2):
def self.process_batch(support_agent_id:, targets:, user_id:, entity_id:, with_steps: false, execution_mode: :adhoc_batch)
  targets = targets.includes(:portfolio_kpi_reports, :documents, :valuations) if targets.respond_to?(:includes)

  run_batch(
    support_agent_id: support_agent_id,
    targets: targets,
    user_id: user_id,
    entity_id: entity_id,
    execution_mode: execution_mode
  )
end
```

**Why:** Product decided that chart generation and compliance checking are separate concerns. A client may want one without the other. Chart Agent will be a separate SupportAgent type on the agents page, invoked independently.

**Also removed:** The `generate_portfolio_insights` call that was planned in v1. The LLM insights panel has been dropped from the dashboard.

**Additional fix (v2.1):** The generic loop in `SupportAgentJob#perform` (Path 2 — for agents without `process_batch`, or when invoked via `run_with_steps` with Entity target) was calling `agent.wtf?` without `batch_mode: true`. This caused per-company `AgentChartJob` to fire even in batch runs. Fixed by passing `batch_mode: is_batch_run` in the generic loop's `wtf?` call.

**File:** `app/packs/ai/support_agents/jobs/support_agent_job.rb`

```ruby
# Line 159 — added batch_mode: is_batch_run
support_agent.agent.wtf?(
  support_agent_id: support_agent_id,
  target: target,
  user_id: user_id,
  entity_id: support_agent.entity_id,
  batch_mode: is_batch_run,
  rta_pdf_document_id: rta_pdf_document_id
)
```

---

### 6. File Summary

| File | Action | Purpose |
|------|--------|---------|
| `app/packs/ai/support_agents/services/portfolio_dashboard_presenter.rb` | **Modify** | Add `document_types`, `document_ok?`; fix `issues_by_type`; remove insights methods |
| `app/packs/ai/support_agents/views/support_agents/_portfolio_reports_tab.html.erb` | **Modify** | Move filter controller to wrapper div; remove sidebar + charts rows |
| `app/packs/ai/support_agents/views/support_agents/_portfolio_dashboard_stats.html.erb` | **Modify** | Add click-to-filter `data-action` + `status-param` on each card |
| `app/packs/ai/support_agents/views/support_agents/_portfolio_dashboard_chart.html.erb` | **No change** | Bar chart already dynamic; presenter fix handles document breakdown |
| `app/packs/ai/support_agents/views/support_agents/_portfolio_dashboard_actions.html.erb` | **Modify** | Turbo-enabled Run Validation button + `#portfolio_batch_progress_panel` div |
| `app/packs/ai/support_agents/views/support_agents/_batch_progress_panel.html.erb` | **Modify** | Accept optional `panel_id` local for dynamic DOM ID |
| `app/packs/ai/support_agents/jobs/support_agent_job.rb` | **Modify** | Pass `batch_mode: is_batch_run` in generic loop `wtf?` call |
| `app/packs/ai/support_agents/views/support_agents/_portfolio_dashboard_table.html.erb` | **Rewrite** | Dynamic document columns, full-width, dynamic colspan, data-issues attr |
| `app/packs/ai/support_agents/views/support_agents/_portfolio_dashboard_footer.html.erb` | **No change** | Recommended next steps + last run info |
| `app/packs/ai/support_agents/views/support_agents/_portfolio_dashboard_insights.html.erb` | **Delete** | Insights sidebar removed |
| `app/packs/ai/support_agents/views/support_agents/_portfolio_dashboard_overdue.html.erb` | **Delete** | Overdue sidebar removed |
| `app/packs/ai/support_agents/views/support_agents/_portfolio_dashboard_kpi_charts.html.erb` | **Delete** | Charts decoupled |
| `app/packs/ai/support_agents/views/support_agents/_portfolio_report_detail.html.erb` | **Keep** | Existing detail view (used inside table rows) |
| `app/javascript/controllers/portfolio_dashboard_chart_controller.js` | **No change** | Chart.js bar chart rendering |
| `app/javascript/controllers/portfolio_dashboard_filter_controller.js` | **Modify** | Add `filterByStatus`, `_filterCustom`; guard target presence |
| `app/packs/ai/support_agents/controllers/support_agents_controller.rb` | **Modify** | Remove AgentChart loading |
| `app/packs/ai/support_agents/services/portfolio_company_agent.rb` | **Modify** | Remove `AgentChartJob` from `process_batch` block |

---

### 7. Implementation Sequence

| Step | What | Dependencies |
|------|------|-------------|
| 1 | Update `PortfolioDashboardPresenter` — add `document_types`, `document_ok?`; fix `issues_by_type`; remove insights methods; make `total_possible_issues` dynamic | None |
| 2 | Update controller — remove `@portfolio_agent_charts` loading | None |
| 3 | Update `_portfolio_reports_tab.html.erb` — move filter controller to wrapper, remove sidebar + charts rows | Steps 1-2 |
| 4 | Update `_portfolio_dashboard_stats.html.erb` — add clickable stat card markup | Step 3 |
| 5 | Rewrite `_portfolio_dashboard_table.html.erb` — dynamic document columns, full-width | Step 1 |
| 6 | Update `portfolio_dashboard_filter_controller.js` — add `filterByStatus`, `_filterCustom` | Steps 4-5 |
| 7 | Delete `_portfolio_dashboard_insights.html.erb` | Step 3 |
| 8 | Delete `_portfolio_dashboard_overdue.html.erb` | Step 3 |
| 9 | Delete `_portfolio_dashboard_kpi_charts.html.erb` | Step 3 |
| 10 | Update `portfolio_company_agent.rb` — remove `AgentChartJob` from `process_batch` | None |
| 11 | End-to-end testing on dev | All steps |

### 8. Phase 2 (Post-Launch)

| Feature | Notes |
|---------|-------|
| Send Reminders button (enabled) | New controller action that triggers KPI reminder for all overdue companies — sends only to companies that still haven't uploaded |
| Generate Report on email | New job that compiles SupportAgentReports into PDF and emails |
| Historical trend comparison | Compare current quarter stats vs. previous quarter |
| Export Tracker (Excel/PDF) | Export the company table as Excel or PDF |
| Pagination for large portfolios | Pagy integration if >20 companies |
| Chart Agent as separate SupportAgent | Separate agent type for KPI chart generation, independent of compliance checking |
| Portfolio Insights (LLM-generated) | Revisit if product wants AI-generated insights in a future iteration |
