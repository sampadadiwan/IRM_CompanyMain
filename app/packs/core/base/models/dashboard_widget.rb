class DashboardWidget < ApplicationRecord
  acts_as_list scope: %i[owner dashboard_name entity_id]
  belongs_to :entity
  belongs_to :owner, polymorphic: true, optional: true

  validates :dashboard_name, :widget_name, :size, :tags, presence: true
  validates :dashboard_name, length: { maximum: 30 }
  validates :widget_name, length: { maximum: 30 }
  # Layout names carry company tags for LP layouts ("LP, FinTech") — E89
  validates :name, length: { maximum: 100 }, allow_blank: true
  # X6 — an LP layout only takes widgets that are safe to show LPs
  validate :lp_safe_in_lp_layout
  validates :size, length: { maximum: 10 }
  validates :tag_list, length: { maximum: 20 }, allow_blank: true
  validates :tags, length: { maximum: 100 }
  # C1 — metadata is read as a plain literal, never evaluated; refuse anything else when it changes
  validate :metadata_must_be_literal, if: :will_save_change_to_metadata?

  # LP layouts: Portfolio Company Dashboard layouts whose comma-separated name includes the tag "LP" ("LP",
  # "LP, FinTech"). The company's tags pick one for each shared company (LpLayoutResolver); only these widget
  # types can be placed in one. Worked examples X6, E52, E88–E90 — openspec/changes/lp-folio-portfolio-dashboard/business-rules.md
  LP_LAYOUT_TOKEN = "lp".freeze
  LP_SAFE_WIDGET_NAMES = ["Data Card", "Key Kpis", "Kpis", "Kpis Performance Table", "Valuations",
                          "Portfolio Investments", "Portfolio Stats", "Embed Document"].freeze
  # LP-safe widgets that read KPI data: offered and shown only when the fund manager has the KPI module (E97)
  LP_KPI_WIDGET_NAMES = ["Key Kpis", "Kpis", "Kpis Performance Table"].freeze
  # What "Set up LP layout" starts the "LP" layout with
  LP_STARTER_WIDGETS = ["Data Card", "Key Kpis", "Valuations"].freeze
  # Starter settings so a new LP layout is not blank: the Data Card shows a few company fields
  LP_STARTER_METADATA = { "Data Card" => '{fields: "Category:category,Sector:sector,City:city", title: "Summary"}' }.freeze
  LP_UNSAFE_MESSAGE = "This widget can't be added to an LP layout: it isn't safe to show LPs.".freeze
  # C1 — shown on the form and in import row errors when metadata is not a plain literal
  METADATA_LITERAL_MESSAGE = "can only contain plain values: text, numbers, true/false, nil, [lists] and {key: value} hashes. " \
                             "Calculations and code are not allowed".freeze

  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :for_dashboard, ->(dashboard_name) { where(dashboard_name: dashboard_name) }
  scope :widget_name, ->(widget_name) { where(widget_name: widget_name) }
  scope :with_size, ->(size) { where(size: size) }

  # The path to the widget partial to be rendered
  attr_accessor :path
  # metadata help text to be show in the UI, to help users understand what metadata can be passed
  attr_writer :metadata_help

  def metadata_help
    @metadata_help || self.class.definitions_map[[dashboard_name, widget_name]]&.instance_variable_get(:@metadata_help)
  end

  def self.definitions_map
    @definitions_map ||= all_widgets.index_by { |w| [w.dashboard_name, w.widget_name] }
  end

  # Label, one-line help, whole-number flag and pick-list source for the settings on the Widget Configuration form,
  # keyed by widget name then setting key. Settings without an entry render as before (humanized key).
  # H3, H4, H5, H8, H14 — openspec/changes/fix-portfolio-dashboard-widgets/design.md#worked-examples
  # The stats widgets' card picker and labels, shared by the company and fund-level widgets
  STATS_FIELD_HINTS = {
    "fields" => { label: "Fields", choices: :stats_fields, multiple: true, hint: "Pick the cards to show, in order." },
    "field_names" => { label: "Field names",
                       hint: "List the names in the same order as the Fields you picked, separated by commas. " \
                             "E.g. Bought Amount, Sold Amount, FMV → Buy, Sell, Fair value" },
    "force_units" => { label: "Units" },
    "per_row" => { label: "Cards per row", integer: true }
  }.freeze

  # Settings of the insight widgets (H2, E1, E2 — openspec/changes/archive/2026-11-07-dashboard-insight-widgets/business-rules.md#1).
  # A missing, zero, negative or non-numeric whole-number setting falls back to the default named in the hint.
  INSIGHT_KPI_REPORT_HINTS = {
    "tag_list" => { label: "Report tag", hint: "Which KPI reports to read, e.g. Actual or Budget. Default Actual." },
    "period" => { label: "Report period", hint: "Month, Quarter, Year or YTD. The latest report with this period is used. Default Quarter." }
  }.freeze

  INSIGHT_FIELD_HINTS = {
    "KPI Movers" => INSIGHT_KPI_REPORT_HINTS.merge(
      "top_n" => { label: "Rows to show", integer: true, hint: "How many KPIs to list, biggest change first. Default 5." }
    ),
    "KPI Threshold Watch" => INSIGHT_KPI_REPORT_HINTS,
    "Peer KPI Comparison" => INSIGHT_KPI_REPORT_HINTS.merge(
      "kpi_name" => { label: "KPI name", hint: "The KPI to compare, by its reported or standard name, e.g. Revenue." }
    ),
    "Investment Timeline" => {
      "period" => { label: "Group by", hint: "quarter or year. Default quarter." }
    },
    "Valuation Freshness" => {
      "current_days" => { label: "Current up to (days)", integer: true,
                          hint: "A valuation this many days old or newer is Current. Default 90." },
      "due_days" => { label: "Due up to (days)", integer: true,
                      hint: "Older than Current but up to this many days is Due; older is Stale. Default 180." },
      "limit" => { label: "Rows to show", integer: true, hint: "How many companies to list, oldest valuation first. Default 15." }
    },
    "Winners & Losers" => {
      "top_n" => { label: "Rows per list", integer: true, hint: "How many gains and how many losses to list. Default 5." }
    },
    "Sector Exposure" => {
      "measure" => { label: "Measure", hint: "fmv (current fair value) or cost (cost of the holdings still held). Default fmv." }
    },
    "NAV per Unit Trend" => {
      "months" => { label: "Months", integer: true, hint: "How many months to plot, up to the latest approved NAV. Default 12." }
    },
    "Hedge Expiries" => {
      "days" => { label: "Expiring within (days)", integer: true,
                  hint: "List open contracts expiring within this many days, and any already expired. Default 90." }
    },
    "Investor Pending Actions" => {
      "kyc_expiry_days" => { label: "KYC expiry warning (days)", integer: true,
                             hint: "List a verified KYC that expires within this many days. Default 60." }
    },
    "Side-letter Obligations" => {
      "days" => { label: "Due within (days)", integer: true,
                  hint: "List active obligations due within this many days, and any overdue. Default 30." }
    },
    "Overdue Tasks by Assignee" => {
      "top_n" => { label: "People to show", integer: true, hint: "The rest are grouped as Others. Default 10." }
    },
    "Stuck Workflows" => {
      "days" => { label: "Waiting at least (days)", integer: true,
                  hint: "List journeys that have been on their current step this many days or more. Default 7." },
      "limit" => { label: "Rows to show", integer: true, hint: "How many journeys to list, longest wait first. Default 10." }
    }
  }.freeze

  METADATA_FIELD_HINTS = {
    "Kpis" => {
      "compound" => { label: "Data-only view",
                      hint: "ON groups KPIs by category and shows data only (chart selection is off). " \
                            "OFF shows the full table with a plot checkbox per KPI." },
      "show_action_buttons" => { label: "Show action buttons",
                                 hint: "ON shows the heading and the filter, chart and settings buttons above the table. OFF by default." }
    },
    "Kpis Budget vs Actual" => {
      "category" => { label: "Default category", hint: "Category pre-selected in the filter above the table." }
    },
    "Documents" => {
      "owner_id" => { label: "Owner ID", integer: true,
                      hint: "Whole number: the ID of the Investor or Valuation whose documents to show. Leave empty for this company." },
      "folder_id" => { label: "Folder ID", integer: true,
                       hint: "Whole number: the ID of any folder you may see. Leave empty for the company's own folder." }
    },
    "Portfolio Investments" => {
      "group_by_column" => { label: "Group by column", choices: :portfolio_investment_columns,
                             hint: "Rows are grouped by this column. Choosing one uses the AG grid, whatever the Ag setting." }
    },
    # H1, H2, H3, E12, E17, E18 — openspec/changes/fix-portfolio-dashboard-widgets-2/design.md#worked-examples
    "Portfolio Stats" => STATS_FIELD_HINTS.merge(
      "currency" => { label: "Default currency", choices: :entity_currencies,
                      hint: "Order: picked on page > Tracking currency (if ON) > Default currency > firm's currency" }
    ),
    "Fund Portfolio Stats" => STATS_FIELD_HINTS,
    # H9 — openspec/changes/fix-portfolio-dashboard-widgets-2/design.md#worked-examples
    "Data Card" => {
      "fields" => { label: "Fields",
                    hint: "Standard field: a label, a colon, then the field name, e.g. Category:category, Sector:sector, " \
                          "City:city. Custom field: the same, with custom_fields. before the name, e.g. " \
                          "KPI Currency:custom_fields.kpi_currency. Separate entries with commas." }
    }
  }.merge(INSIGHT_FIELD_HINTS).freeze

  def self.field_hint(widget_name, key)
    METADATA_FIELD_HINTS.dig(widget_name.to_s, key.to_s)
  end

  FM_LANDING_PAGE = "FM Landing Page".freeze
  LP_LANDING_PAGE = "LP Landing Page".freeze
  OPS_LANDING_PAGE = "Ops Landing Page".freeze
  FUND_DASHBOARD = "Fund Dashboard".freeze
  OPS_DASHBOARD = "Ops Dashboard".freeze
  INVESTOR_DASHBOARD = "Investor Dashboard".freeze
  PORTFOLIO_COMPANY_DASHBOARD = "Portfolio Company Dashboard".freeze
  PORTFOLIO_DASHBOARD = "Portfolio Dashboard".freeze
  AGGREGATED_PORTFOLIO_DASHBOARD = "Aggregated Portfolio Dashboard".freeze

  FUND_WIDGETS = [
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Fund Stats", path: "funds/fund_stats", size: "XL"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Fund Card", path: "funds/card", size: "XL"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Fund Ratios", path: "funds/widgets/fund_ratios", size: "Medium", metadata_help: "{title: 'Title', scenario: 'Default', scenarios: 'Actual,Budget', fund: true, owner_type: ['Fund','User'], owner_id: [1,2,3], latest: true, end_date:'31-03-2025', condensed: true, chart: false, list: true, months: 12, ratio_names: ['XIRR', 'TVPI', 'DPI'], show_y_axis: true, show_legend: true, decimals: 2, hide_fund_name: false }"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Commitment Breakup", path: "funds/widgets/commitment_breakup", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Fund Cashflows", path: "funds/widgets/fund_cashflows", size: "Medium", metadata_help: "{months: 36, series: 'Collected Capital, Portfolio Investments', cumulative: false, chart_type: 'line/bar/area/spline'}"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Fund Distributions", path: "funds/widgets/fund_distributions", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Fund Account Entries", path: "funds/widgets/fund_account_entries", size: "Medium", metadata_help: "{months: 12, entry_types: ['Expense', 'Fee'], use_entries: 'folio_only/fund_only'}"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Fund Portfolios", path: "aggregate_portfolio_investments/widgets/portfolio_investments", size: "XL"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Fund Portfolio Stats", path: "aggregate_portfolio_investments/widgets/stats", size: "XL", metadata_help: "{fields: 'Bought Amount,Sold Amount,...', field_names: 'Bought, Sold,...', force_units: 'Lakhs/Crores/Millions', decimals: 2, per_row: 4}"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Fund Report", path: "funds/widgets/fund_report", size: "XL", metadata_help: "{report_id: 1, title: 'Report Title', investor_id: 123, fund_id: 456, parent_name: 'Name', other_report_args: '...' }"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Embed Document", path: "funds/widgets/embedded_doc", size: "XL", metadata_help: "{name: 'Document Name', xlsx_as_grid: true, title: 'Optional Title'}"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Commitment Deployment", path: "capital_commitments/widgets/deployment", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Investor Concentration", path: "capital_commitments/widgets/investor_concentration", size: "Medium", metadata_help: "{top_n: 10, compact: true}"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "GP vs LP Commitment", path: "capital_commitments/widgets/gp_lp_commitment", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Unit Type Distribution", path: "capital_commitments/widgets/unit_type_distribution", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Onboarding Status", path: "capital_commitments/widgets/onboarding_status", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Fundraising Timeline", path: "capital_commitments/widgets/fundraising_timeline", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Currency Exposure", path: "capital_commitments/widgets/currency_exposure", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Call Collection Status", path: "capital_calls/widgets/collection_status", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Capital Call History", path: "capital_calls/widgets/call_history", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Call Collection Efficiency", path: "capital_calls/widgets/collection_efficiency", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Call Fee Breakdown", path: "capital_calls/widgets/fee_breakdown", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Investor Call Dues", path: "capital_calls/widgets/investor_dues", size: "Medium", metadata_help: "{top_n: 10}"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Distribution Status", path: "capital_distributions/widgets/distribution_status", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Distribution History", path: "capital_distributions/widgets/distribution_history", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Distribution Components", path: "capital_distributions/widgets/component_breakdown", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Investor Distributions", path: "capital_distributions/widgets/investor_distributions", size: "Medium", metadata_help: "{top_n: 10}"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Cumulative Distributions", path: "capital_distributions/widgets/cumulative_distributions", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Remittance Status", path: "capital_remittances/widgets/status", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Remittance Progress", path: "capital_remittances/widgets/collection_progress", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Delinquent Investors", path: "capital_remittances/widgets/delinquent_investors", size: "Medium", metadata_help: "{top_n: 10}"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Remittance Fees", path: "capital_remittances/widgets/fee_breakdown", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Remittance Timeline", path: "capital_remittances/widgets/payment_timeline", size: "Medium", metadata_help: "{chart_type: 'bar/spline/line', months: 12, aggregate_by: 'day/quarter/year'}"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Portfolio Allocation", path: "aggregate_portfolio_investments/widgets/allocation", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Investment Performance", path: "aggregate_portfolio_investments/widgets/performance", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Realized vs Unrealized", path: "aggregate_portfolio_investments/widgets/gain_breakdown", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Instrument Exposure", path: "aggregate_portfolio_investments/widgets/instrument_exposure", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Portfolio Income", path: "aggregate_portfolio_investments/widgets/income_by_company", size: "Medium"),
    # Insight widgets — openspec/changes/archive/2026-11-07-dashboard-insight-widgets (business-rules.md §5)
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Remittance Ageing", path: "capital_remittances/widgets/ageing", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "NAV per Unit Trend", path: "evergreen/widgets/nav_per_unit_trend", size: "Medium", metadata_help: "{months: 12}"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Hedge Expiries", path: "derivative_contracts/widgets/hedge_expiries", size: "Medium", metadata_help: "{days: 90}"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Account Entries Chart", path: "capital_commitments/widgets/account_entries_chart", size: "Medium", metadata_help: "{account_entry_names: 'Management Fee, Setup Fee', entry_name: '...', chart_type: 'column/pie/line', aggregate_by: 'quarter/year/sum', period_type: 'quarter', number_of_periods: 8, no_of_periods: 8, compact: true, use_entries: 'folio_only/fund_only'}")
  ].freeze

  OPS_WIDGETS = [
    DashboardWidget.new(dashboard_name: OPS_DASHBOARD, widget_name: "My Tasks", path: "dashboard_widgets/widgets/my_tasks", size: "Medium"),
    DashboardWidget.new(dashboard_name: OPS_DASHBOARD, widget_name: "Upcoming Events", path: "dashboard_widgets/widgets/events", size: "Medium"),
    DashboardWidget.new(dashboard_name: OPS_DASHBOARD, widget_name: "Investors No Interaction", path: "dashboard_widgets/widgets/investors_no_interaction", size: "Medium", metadata_help: "{days: 30, categories: 'Category1, Category2'}"),
    DashboardWidget.new(dashboard_name: OPS_DASHBOARD, widget_name: "Notes", path: "dashboard_widgets/widgets/notes", size: "Medium"),
    # Insight widgets — openspec/changes/archive/2026-11-07-dashboard-insight-widgets (business-rules.md §7)
    DashboardWidget.new(dashboard_name: OPS_DASHBOARD, widget_name: "Needs Attention", path: "funds/widgets/needs_attention", size: "XL"),
    DashboardWidget.new(dashboard_name: OPS_DASHBOARD, widget_name: "Overdue Tasks by Assignee", path: "dashboard_widgets/widgets/overdue_tasks_by_assignee", size: "Medium", metadata_help: "{top_n: 10}"),
    DashboardWidget.new(dashboard_name: OPS_DASHBOARD, widget_name: "Stuck Workflows", path: "dashboard_widgets/widgets/stuck_workflows", size: "Medium", metadata_help: "{days: 7, limit: 10}"),
    DashboardWidget.new(dashboard_name: OPS_DASHBOARD, widget_name: "Side-letter Obligations", path: "side_letter_obligations/widgets/due", size: "Medium", metadata_help: "{days: 30}")
  ].freeze

  INVESTOR_WIDGETS = [

    DashboardWidget.new(dashboard_name: INVESTOR_DASHBOARD, widget_name: "Documents", path: "investors/widgets/documents", size: "XL", metadata_help: "{owner_type: 'Investor'/'Valuation', owner_id: 123, folder_id: 123, include_sub_folders: false, card_view: true, per_page: 6, per_row: 3, show_owner: false, show_tags: false, show_action_buttons: true}"),
    DashboardWidget.new(dashboard_name: INVESTOR_DASHBOARD, widget_name: "My Tasks", path: "dashboard_widgets/widgets/my_tasks", size: "Medium"),
    DashboardWidget.new(dashboard_name: INVESTOR_DASHBOARD, widget_name: "Upcoming Events", path: "dashboard_widgets/widgets/events", size: "Medium"),
    DashboardWidget.new(dashboard_name: INVESTOR_DASHBOARD, widget_name: "Notes", path: "dashboard_widgets/widgets/notes", size: "Medium"),
    DashboardWidget.new(dashboard_name: INVESTOR_DASHBOARD, widget_name: "KYCs", path: "investors/widgets/kycs", size: "Medium"),
    DashboardWidget.new(dashboard_name: INVESTOR_DASHBOARD, widget_name: "Commitments", path: "investors/widgets/commitments", size: "Medium"),
    DashboardWidget.new(dashboard_name: INVESTOR_DASHBOARD, widget_name: "Embed Document", path: "investors/widgets/embedded_doc", size: "XL", metadata_help: "{name: 'Document Name', xlsx_as_grid: true, title: 'Optional Title'}"),
    DashboardWidget.new(dashboard_name: INVESTOR_DASHBOARD, widget_name: "Fund Ratios", path: "investors/widgets/fund_ratios", size: "XL", metadata_help: "{title: 'Title', scenario: 'Default', scenarios: 'Actual,Budget', condensed: true, chart: false, chart_type: 'line or bar or area', list: true, months: 12, latest: false, end_date: '31-12-2025', ratio_names: ['XIRR', 'TVPI', 'DPI'], show_y_axis: true, show_legend: true, decimals: 2, hide_fund_name: false, for_commitments: true, timeseries: true }"),
    DashboardWidget.new(dashboard_name: INVESTOR_DASHBOARD, widget_name: "Note Summaries", path: "dashboard_widgets/widgets/note_summaries", size: "XL", metadata_help: "{title: 'Note Summaries'}"),
    # Insight widgets — openspec/changes/archive/2026-11-07-dashboard-insight-widgets (business-rules.md §6)
    DashboardWidget.new(dashboard_name: INVESTOR_DASHBOARD, widget_name: "Investor Pending Actions", path: "funds/widgets/investor_pending_actions", size: "XL", metadata_help: "{kyc_expiry_days: 60}"),
    DashboardWidget.new(dashboard_name: INVESTOR_DASHBOARD, widget_name: "Side-letter Obligations", path: "side_letter_obligations/widgets/due", size: "Medium", metadata_help: "{days: 30}")

  ].freeze

  PORTFOLIO_COMPANY_WIDGETS = [

    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Valuations", path: "investors/widgets/valuations", size: "XL"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Fund Ratios", path: "investors/widgets/fund_ratios", size: "XL", metadata_help: "{title: 'Title', scenario: 'Default', scenarios: 'Actual,Budget', condensed: true, chart: false, chart_type: 'line or bar or area', list: true, months: 12, latest: false, end_date: '31-12-2025', ratio_names: ['XIRR', 'TVPI', 'DPI'], show_y_axis: true, show_legend: true, decimals: 2, hide_fund_name: false }"),

    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Kpis", path: "investors/widgets/kpis_grid_view", size: "XL", metadata_help: "{title_suffix: 'Title Suffix', chart: false, tag_list: 'Actual,Budget', show_tags: false, compound: false, period: 'Quarter', no_of_periods: 12, show_action_buttons: false, categories: 'Balance Sheet, Income Statement', force_units: 'Lakhs/Crores/Millions', decimals: 2, flexible_chart: true, category: 'General'}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Kpis Performance Table", path: "investors/widgets/performance_table", size: "XL"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Kpis Budget vs Actual", path: "investors/widgets/kpis_budget_vs_actual", size: "XL", metadata_help: "{category: 'Income Statement', tag_list: 'Actual,Budget', units: 'Lakhs', num_periods: 2, period: 'Year', title: 'Budget vs Actual', decimals: 1}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Data Card", path: "investors/widgets/data_card", size: "XL", metadata_help: '{fields: "Category:category,City:city,Sector:custom_fields.sector,Founder:custom_fields.founder", title: "Summary"}'),

    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Portfolio Investments", path: "aggregate_portfolio_investments/widgets/portfolio_investments", size: "XL", metadata_help: "{ag: true, group_by_column: 'investment_instrument_name', show_fund_name: true}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Documents", path: "investors/widgets/documents", size: "XL", metadata_help: "{folder_name: 'My Documents', owner_type: 'Investor'/'Valuation', owner_id: 123, folder_id: 123, include_sub_folders: false, card_view: true, per_page: 6, per_row: 3, show_owner: false, show_tags: false, show_action_buttons: true, documents_as_tags: false}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "My Tasks", path: "dashboard_widgets/widgets/my_tasks", size: "Medium"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Upcoming Events", path: "dashboard_widgets/widgets/events", size: "Medium"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Notes", path: "dashboard_widgets/widgets/notes", size: "XL", metadata_help: "{title: 'Imp Notes'}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Value Bridge", path: "investors/widgets/value_bridge", size: "XL", metadata_help: "{instruments: 'All or Specified in stakeholder custom field called value_bridge_instruments', across: 'First Last or Last 2', show_form: true, hide_table: false, date_format: '%b %Y', decimals: 2, title: 'Value Bridge'}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Captable", path: "investments/widgets/captable", size: "XL", metadata_help: "{show_charts: true, diluted_chart: 'pie/donut/half_donut', show_investments: false, show_captable: true, self_by_funding_round: true, amount_by_funding_round: true, diluted_share_holdings: true, amount_by_investor: true, each_funding_round: false, show_quantity_actual: false, show_quantity_diluted: false, ag: true, investment_type: 'Equity', investor_name: 'Name', category: 'Common', funding_round: 'Series A'}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Portfolio Company Report", path: "funds/widgets/fund_report", size: "XL", metadata_help: "{report_id: 1, title: 'Valuations', show_table: true, show_chart: true, chart_type: 'DonutChart,LineChart,ColumnChart,SplineChart,AreaChart,PieChart,HalfDonutChart', show_prefix: false, show_name: true, show_inputs: false, show_tags: true, show_instrument: false, other_report_args: '...' }"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Portfolio Report", path: "investors/widgets/portfolio_report", size: "XL", metadata_help: "{tabs: 'Tab1, Tab2', portfolio_report_id: 123, title: 'Optional Title'}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Key Kpis", path: "investors/widgets/kpi_key_numbers", size: "XL"),

    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Portfolio Stats", path: "aggregate_portfolio_investments/widgets/stats", size: "XL", metadata_help: "{fields: 'Bought Amount,Sold Amount,...', field_names: 'Bought, Sold,...', force_units: 'Lakhs/Crores/Millions', tracking_currency: true, decimals: 2, currency: 'USD', per_row: 4, show_currency_filter: true}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Embed Document", path: "investors/widgets/embedded_doc", size: "XL", metadata_help: "{name: 'Document Name', xlsx_as_grid: true, title: 'Optional Title'}"),

    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Agent Chart", path: "investors/widgets/agent_chart", size: "XL", metadata_help: "{title: 'Chart Title', height: 420}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Scoring Report", path: "investors/widgets/scoring_report", size: "XL", metadata_help: "{title: 'Company Score', agent_type: 'PortfolioScoringAgent'}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Note Summaries", path: "dashboard_widgets/widgets/note_summaries", size: "XL", metadata_help: "{title: 'Note Summaries'}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Presentation Analyst", path: "investors/widgets/presentation_analyst", size: "XL", metadata_help: "{title: 'Investor Presentation Analysis', last_n: 6}"),

    # Insight widgets — openspec/changes/archive/2026-11-07-dashboard-insight-widgets (business-rules.md §2, §3)
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "KPI Movers", path: "investors/widgets/kpi_movers", size: "Medium", metadata_help: "{top_n: 5, tag_list: 'Actual', period: 'Quarter/Month/Year/YTD'}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "KPI Threshold Watch", path: "investors/widgets/kpi_threshold_watch", size: "Medium", metadata_help: "{tag_list: 'Actual', period: 'Quarter/Month/Year/YTD'}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Monitoring Status", path: "investors/widgets/monitoring_status", size: "XL"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Investment Timeline", path: "investors/widgets/investment_timeline", size: "Medium", metadata_help: "{period: 'quarter/year'}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Ownership Trend", path: "investors/widgets/ownership_trend", size: "Medium")

  ].freeze

  # Help shown as an info icon on these widgets' titles (WidgetCardComponent)
  WIDGET_HELP = {
    "Portfolio Stats" => "Totals across the fund's portfolio investments",
    "Portfolio Investments" => "Each holding of the fund: what it cost, what was sold and what it is worth now",
    "FMV %" => "Share of the portfolio's current value held in each company",
    "Holding Cost %" => "Share of the cost of current holdings in each company",
    "Bought %" => "Share of the total amount invested that went into each company",
    "Sold %" => "Share of sale proceeds that came from each company",
    "Portfolio IRR" => "Annualised return (IRR) and multiple (MOIC) on each portfolio company",
    # Insight widgets — openspec/changes/archive/2026-11-07-dashboard-insight-widgets
    "KPI Movers" => "The KPIs that moved most on the company's latest report against the previous report of the " \
                    "same period. Set the report tag, period and rows in the widget settings.",
    "KPI Threshold Watch" => "KPIs on the latest report rated red or amber, or whose change broke a threshold set in KPI " \
                             "Mappings. Set thresholds there to get flags.",
    "Monitoring Status" => "The portfolio company agent's latest check of this company: KPIs submitted, required documents " \
                           "received and valuation up to date. All companies opens the full agent dashboard.",
    "Investment Timeline" => "Purchases and sales in this company per quarter or year, in the firm's currency, across the " \
                             "funds you can open.",
    "Ownership Trend" => "Fully diluted ownership per holder group (Founder, Self, Employee, Other) on each approved " \
                         "cap-table date.",
    "Valuation Freshness" => "How long ago each company was last valued: Current, Due, Stale or Never, by the day limits in " \
                             "the widget settings. Stalest first.",
    "Winners & Losers" => "The companies furthest above and below cost in this fund: unrealised gain = fair value − cost " \
                          "of the remaining holding.",
    "Sector Exposure" => "The fund's holdings by the portfolio company's sector, by fair value or by cost (widget " \
                         "settings).",
    "Peer KPI Comparison" => "One KPI (set in the widget settings) across the companies on this page, from each company's " \
                             "latest report, biggest change first.",
    "Remittance Ageing" => "Money still owed on this fund's capital calls, grouped by days past the call's due date. View " \
                           "open remittances lists the same rows.",
    "NAV per Unit Trend" => "Approved NAV per unit for each unit class over the last months (widget settings). Evergreen " \
                            "funds only.",
    "Hedge Expiries" => "Open derivative contracts expiring within the window in the widget settings, and any past " \
                        "expiry but still open.",
    "Investor Pending Actions" => "Everything still open with this investor, in four parts: unpaid capital calls, KYCs to verify or " \
                                  "refresh, approvals awaiting their reply and documents awaiting their signature. Each count " \
                                  "covers every matching record and opens the full list; each table shows the first 5.",
    "Side-letter Obligations" => "Approved, active side-letter obligations due within the window in the widget settings, and any " \
                                 "overdue, earliest first.",
    "Needs Attention" => "Work that is stuck right now: overdue tasks, KYCs to verify, overdue remittances and open " \
                         "e-sign requests. Each card opens the list it counts.",
    "Overdue Tasks by Assignee" => "Open tasks past their due date, per person, most first; the rest grouped as Others. View " \
                                   "overdue tasks opens the same list.",
    "Stuck Workflows" => "Active journeys waiting on the same step for at least the days in the widget settings, longest " \
                         "wait first."
  }.freeze

  # Portfolio Dashboard widgets an LP keeps under an Allocated LP portfolio view: the holdings list, which the
  # policy scopes narrow to the LP's folio (E42 — openspec/changes/lp-folio-portfolio-dashboard/business-rules.md)
  LP_ALLOCATED_PORTFOLIO_WIDGETS = ["Portfolio Investments"].freeze

  PORTFOLIO_WIDGETS = [
    DashboardWidget.new(dashboard_name: PORTFOLIO_DASHBOARD, widget_name: "Portfolio Stats", path: "aggregate_portfolio_investments/widgets/stats", size: "XL", metadata_help: "{fields: 'Bought Amount,Sold Amount,...', field_names: 'Bought, Sold,...', force_units: 'Lakhs/Crores/Millions', decimals: 2, per_row: 4}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_DASHBOARD, widget_name: "Portfolio Investments", path: "aggregate_portfolio_investments/widgets/portfolio_investments", size: "XL", metadata_help: "{ag: true, group_by_column: 'investment_instrument_name', show_fund_name: true/false}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_DASHBOARD, widget_name: "FMV %", path: "aggregate_portfolio_investments/widgets/fmv_percentage", size: "Medium"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_DASHBOARD, widget_name: "Holding Cost %", path: "aggregate_portfolio_investments/widgets/holding_costs_percentage", size: "Medium"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_DASHBOARD, widget_name: "Bought %", path: "aggregate_portfolio_investments/widgets/bought_percentage", size: "Medium"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_DASHBOARD, widget_name: "Sold %", path: "aggregate_portfolio_investments/widgets/sold_percentage", size: "Medium"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_DASHBOARD, widget_name: "Portfolio IRR", path: "aggregate_portfolio_investments/widgets/irr", size: "XL", metadata_help: "{show_table: false, show_chart: false}"),
    # Insight widgets — openspec/changes/archive/2026-11-07-dashboard-insight-widgets (business-rules.md §4)
    DashboardWidget.new(dashboard_name: PORTFOLIO_DASHBOARD, widget_name: "Valuation Freshness", path: "aggregate_portfolio_investments/widgets/valuation_freshness", size: "XL", metadata_help: "{current_days: 90, due_days: 180, limit: 15}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_DASHBOARD, widget_name: "Winners & Losers", path: "aggregate_portfolio_investments/widgets/winners_losers", size: "Medium", metadata_help: "{top_n: 5}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_DASHBOARD, widget_name: "Sector Exposure", path: "aggregate_portfolio_investments/widgets/sector_exposure", size: "Medium", metadata_help: "{measure: 'fmv/cost'}")
  ].freeze

  AGGREGATED_WIDGETS = [

    DashboardWidget.new(
      dashboard_name: AGGREGATED_PORTFOLIO_DASHBOARD,
      widget_name: "Aggre. Portfolio Investments",
      path: "aggregate_portfolio_investments/widgets/multicompany_portfolio_investments",
      size: "XL",
      metadata_help: "{show_grouped: true, group_by_column:'portfolio_company_name', decimals:2}",
      position: 1
    ),
    DashboardWidget.new(
      dashboard_name: AGGREGATED_PORTFOLIO_DASHBOARD,
      widget_name: "Stats",
      path: "aggregate_portfolio_investments/widgets/stats",
      size: "XL",
      position: 2,
      metadata_help: "{title: 'Stats', fields: 'Total Bought Amount, Total Sold Amount, Total FMV, Total Cost Of Remaining, Total Income, Sold + FMV', field_names: 'Bought, Sold, FMV, Income', tracking_currency: true, decimals: 3, currency: 'INR', force_units: 'Lakhs', per_row: 4,  show_currency_filter: true}"
    ),
    DashboardWidget.new(dashboard_name: AGGREGATED_PORTFOLIO_DASHBOARD, widget_name: "Company Charts", path: "aggregate_portfolio_investments/widgets/portfolio_company_charts", size: "XL", metadata_help: "{show_sector_wise: true, show_portfolio_company_wise: true , show_table: true, show_chart: true, plot: 'fmv/bought_amount/sold_amount', table_limit: 10, title: 'FMV by Company'}", position: 4),
    DashboardWidget.new(dashboard_name: AGGREGATED_PORTFOLIO_DASHBOARD, widget_name: "Fund Ratios", path: "aggregate_portfolio_investments/widgets/fund_ratio_aggregate", size: "XL", metadata_help: "{show_table: true, show_chart: true, display_mode: 'aggregate/per_company', aggregate_ratio_names: ['Gross Portfolio IRR', 'MOIC', 'RVPI', 'DPI', 'TVPI', 'Portfolio Value to Cost', 'Paid In to Committed Capital'], company_ratio_names: ['IRR', 'MOIC', 'Value To Cost'], titles: ['IRR', 'MOIC'], latest: true, end_date: '31-12-2025', show_y_axis: true, show_legend: true, hide_fund_name: false, positive_colors: ['green', 'DarkOrange'], negative_colors: ['orange', 'red'], decimals: 2, template_names: 'Ecom+AI, AI'}"),
    DashboardWidget.new(dashboard_name: AGGREGATED_PORTFOLIO_DASHBOARD, widget_name: "Company Ratios", path: "aggregate_portfolio_investments/widgets/company_ratios_aggregate", size: "XL", metadata_help: "{show_table: true, show_chart: true, ratio_names: ['IRR', 'MOIC'], titles: ['IRR', 'MOIC'], owner_type: ['Investor'], owner_id: [1,2,3], latest: true, end_date: '31-12-2025', chart_colors: ['green', 'DarkOrange'], negative_colors:['orange', 'red'], decimals: 2}"),
    # Insight widgets — openspec/changes/archive/2026-11-07-dashboard-insight-widgets (business-rules.md §4)
    DashboardWidget.new(dashboard_name: AGGREGATED_PORTFOLIO_DASHBOARD, widget_name: "Valuation Freshness", path: "aggregate_portfolio_investments/widgets/valuation_freshness", size: "XL", metadata_help: "{current_days: 90, due_days: 180, limit: 15}"),
    DashboardWidget.new(dashboard_name: AGGREGATED_PORTFOLIO_DASHBOARD, widget_name: "Peer KPI Comparison", path: "aggregate_portfolio_investments/widgets/peer_kpi_comparison", size: "XL", metadata_help: "{kpi_name: 'Revenue', tag_list: 'Actual', period: 'Quarter/Month/Year/YTD'}")

  ].freeze

  FM_LANDING_PAGE_WIDGETS = [
    # card_type on FM Menus / FM Stats mirrors the Funds widget variants: card (classic),
    # card2 (icon box), card3 (tile grid), card4 (stat strip), card5 (border-top cards)
    DashboardWidget.new(dashboard_name: FM_LANDING_PAGE, widget_name: "FM Menus", path: "entities/widgets/fm_menus", size: "XL", metadata_help: "{card_type: 'card/card2/card3/card4/card5', items: 'Label:path,Label:path', color: 'success/info/primary/warning'}"),
    DashboardWidget.new(dashboard_name: FM_LANDING_PAGE, widget_name: "FM Stats", path: "entities/widgets/fm_stats", size: "XL", metadata_help: "{card_type: 'card/card2/card3/card4/card5'}"),
    # card_type: card (classic), card2 (compact ledger, 2-up), card3 (refined current),
    #            card4 (stat strip, 1 row per fund), card5 (chart-forward donut)
    DashboardWidget.new(dashboard_name: FM_LANDING_PAGE, widget_name: "Funds", path: "entities/widgets/funds", size: "XL", metadata_help: "{card_type: 'card/card2/card3/card4/card5'}"),
    DashboardWidget.new(dashboard_name: FM_LANDING_PAGE, widget_name: "Investment Opportunities", path: "entities/widgets/investment_opportunities", size: "XL"),
    # Insight widget — openspec/changes/archive/2026-11-07-dashboard-insight-widgets (business-rules.md §7, H20). Fifth in the list, so
    # it is not in the 4 landing-page defaults (configured_dashboard_widgets takes the first 4) and appears only once enabled.
    DashboardWidget.new(dashboard_name: FM_LANDING_PAGE, widget_name: "Needs Attention", path: "funds/widgets/needs_attention", size: "XL")
  ].freeze

  LP_LANDING_PAGE_WIDGETS = [
    DashboardWidget.new(dashboard_name: LP_LANDING_PAGE, widget_name: "Funds", path: "entities/widgets/lp_funds", size: "XL", metadata_help: "{card_type: card/card2/stats_card}"),
    DashboardWidget.new(dashboard_name: LP_LANDING_PAGE, widget_name: "Offers", path: "entities/widgets/lp_offers", size: "XL"),
    DashboardWidget.new(dashboard_name: LP_LANDING_PAGE, widget_name: "Interests", path: "entities/widgets/lp_interests", size: "XL"),
    DashboardWidget.new(dashboard_name: LP_LANDING_PAGE, widget_name: "Deals", path: "entities/widgets/lp_deals", size: "XL"),
    DashboardWidget.new(dashboard_name: LP_LANDING_PAGE, widget_name: "Investment Opportunities", path: "entities/widgets/lp_investment_opportunities", size: "XL"),
    DashboardWidget.new(dashboard_name: LP_LANDING_PAGE, widget_name: "Entities", path: "entities/widgets/lp_entities", size: "XL")
  ].freeze

  OPS_LANDING_PAGE_WIDGETS = [
    # Add default widgets for Ops Landing Page here if any
  ].freeze

  WIDGETS = {
    FM_LANDING_PAGE => FM_LANDING_PAGE_WIDGETS,
    LP_LANDING_PAGE => LP_LANDING_PAGE_WIDGETS,
    OPS_LANDING_PAGE => OPS_LANDING_PAGE_WIDGETS,
    FUND_DASHBOARD => FUND_WIDGETS,
    OPS_DASHBOARD => OPS_WIDGETS,
    INVESTOR_DASHBOARD => INVESTOR_WIDGETS,
    PORTFOLIO_COMPANY_DASHBOARD => PORTFOLIO_COMPANY_WIDGETS,
    PORTFOLIO_DASHBOARD => PORTFOLIO_WIDGETS,
    AGGREGATED_PORTFOLIO_DASHBOARD => AGGREGATED_WIDGETS
  }.freeze

  def self.dashboard_names
    [
      FM_LANDING_PAGE,
      LP_LANDING_PAGE,
      OPS_LANDING_PAGE,
      FUND_DASHBOARD,
      PORTFOLIO_DASHBOARD,
      OPS_DASHBOARD,
      INVESTOR_DASHBOARD,
      PORTFOLIO_COMPANY_DASHBOARD,
      AGGREGATED_PORTFOLIO_DASHBOARD
    ].sort
  end

  # The sizes a widget can take, largest first (the widget edit form and the settings popup offer these)
  SIZES = %w[XL Large Medium Small XS].freeze

  # Landing pages show only the first few catalogue widgets by default, to avoid context-specific widget crashes
  LANDING_PAGES = [FM_LANDING_PAGE, LP_LANDING_PAGE, OPS_LANDING_PAGE].freeze
  LANDING_PAGE_DEFAULT_COUNT = 4

  # The default widgets a dashboard shows when its layout has no enabled widget: the whole catalogue, or the
  # first four on the landing pages. Unsaved catalogue entries. The settings popup saves exactly this set on the
  # first save (openspec/changes/archive/2026-11-07-dashboard-widget-inline-settings — H5, E4)
  def self.default_widgets_for(dashboard_name)
    catalogue = WIDGETS.fetch(dashboard_name, [])
    LANDING_PAGES.include?(dashboard_name) ? catalogue.take(LANDING_PAGE_DEFAULT_COUNT) : catalogue
  end

  def to_s
    "#{dashboard_name} #{widget_name} #{tags} #{tag_list}"
  end

  def widget_size
    case size
    when "XS"
      "col-md-3"
    when "Small"
      "col-md-4"
    when "Medium"
      "col-md-6"
    when "Large"
      "col-md-8"
    when "XL"
      "col-md-12"
    else
      "col"
    end
  end

  def self.ransackable_attributes(_auth_object = nil)
    # name: lets guidance links open one layout, e.g. the company's LP layout (E91)
    %w[enabled dashboard_name name widget_name owner_type position tags tag_list]
  end

  # No association is searchable; Ransack 6 asks for this list on any non-column condition and raises without it
  def self.ransackable_associations(_auth_object = nil)
    []
  end

  def self.add_all(entity, owner: nil)
    FUND_WIDGETS.each do |widget|
      dashboard_widget = widget.dup
      dashboard_widget.entity = entity
      dashboard_widget.owner = owner
      dashboard_widget.save
    end
  end

  def self.all_widgets
    WIDGETS.values.flatten
  end

  # Layout name tokens, compared ignoring case and spaces (E82)
  def self.layout_tokens(name)
    name.to_s.split(",").map { |token| token.strip.downcase }.compact_blank
  end

  # Only the exact token "LP" marks an LP layout — "LPX" or "Help" are internal (E90)
  def self.lp_layout_name?(name)
    layout_tokens(name).include?(LP_LAYOUT_TOKEN)
  end

  # The company tags an LP layout is for ("LP, FinTech" -> ["fintech"])
  def self.lp_layout_tags(name)
    layout_tokens(name) - [LP_LAYOUT_TOKEN]
  end

  # The fund manager's LP layout names (distinct names first, filtered in Ruby — a handful per entity)
  def self.lp_layout_names_for(entity_id)
    where(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, entity_id:).distinct.pluck(:name).select { |name| lp_layout_name?(name) }
  end

  def lp_layout?
    dashboard_name == PORTFOLIO_COMPANY_DASHBOARD && self.class.lp_layout_name?(name)
  end

  # Query params that open one layout in the widget list (guidance links)
  def self.layout_filter(name)
    { dashboard_name_eq: PORTFOLIO_COMPANY_DASHBOARD, name_eq: name }
  end

  # The LP-safe widgets for a fund manager: the KPI widgets only with the KPI module (E97)
  def self.lp_safe_widget_names(entity)
    entity&.permissions&.enable_kpis? ? LP_SAFE_WIDGET_NAMES : LP_SAFE_WIDGET_NAMES - LP_KPI_WIDGET_NAMES
  end

  # Widget types offered on the form: an LP layout lists only the LP-safe ones (E52, E97)
  def self.widget_select_for(name, entity)
    return widget_select unless lp_layout_name?(name)

    widget_select.merge(PORTFOLIO_COMPANY_DASHBOARD => widget_select[PORTFOLIO_COMPANY_DASHBOARD] & lp_safe_widget_names(entity))
  end

  def self.widget_select
    WIDGETS.transform_values do |widgets|
      widgets.map(&:widget_name).sort
    end
  end

  # The widget's settings, from the metadata hash literal ({months: 12, ratio_names: %w[XIRR TVPI]}).
  # Built by RubyLiteral without evaluating anything (C1 — docs/security/security_review_2026_10.md).
  def metadata_args
    # C1-X1…X4 — literals (incl. %w[], duplicate keys, escaped quotes, surrounding whitespace) give the
    # same values eval did; blank metadata gives {}
    RubyLiteral.parse_hash(metadata).deep_symbolize_keys
  rescue RubyLiteral::NotLiteral => e
    # C1-2 — a stored expression (e.g. written by update_column, skipping validation) is never run:
    # log it and render the widget with its defaults
    Rails.logger.warn { "DashboardWidget##{id} metadata is not a plain literal, using defaults: #{e.message}" }
    {}
  end

  def metadata_help_hash
    return {}.deep_symbolize_keys if metadata_help.blank?

    # Attempt to sanitize common "help-isms" to make it valid Ruby
    # We want to be careful not to double-quote already quoted strings
    sanitized_help = metadata_help
                     .gsub(/\.\.\.*/, "") # Remove ....
                     .gsub("'/'", "/")    # Fix 'Investor'/'Valuation'
                     .gsub(/(\w+):\s*([,}])/, '\1: nil\2') # Fix empty values like folder_id:,
                     .gsub(/(\w+):\s*([^,}\['"\s]+)\/([^,}\]]+)/) do |match|
                       # Only quote if not already quoted
                       m = Regexp.last_match
                       if m[2].start_with?("'", '"')
                         match
                       else
                         "#{m[1]}: '#{m[2]}/#{m[3]}'"
                       end
                     end
                     .gsub(/,\s*\]/, "]")
                     .gsub(/,\s*\}/, "}")

    # sanitized_help is only cosmetically normalized above; build the hash from the literal without
    # evaluating it (C1). Help text that is not a plain literal raises NotLiteral -> regex fallback below.
    ret_val = RubyLiteral.parse_hash(sanitized_help)
    # Clean up values in the hash
    ret_val.each do |k, v|
      ret_val[k] = v.gsub(/\.\.\.*/, "").gsub(/,\s*$/, "").strip if v.is_a?(String)
    end
    ret_val.deep_symbolize_keys
  rescue StandardError
    # Fallback to a more robust regex-based extractor if the help text is not a plain literal
    extract_keys_from_help.deep_symbolize_keys
  end

  private

  # X6 — refused on create and on an edit that moves a widget into an LP layout
  def lp_safe_in_lp_layout
    return unless lp_layout? && (new_record? || will_save_change_to_name? || will_save_change_to_widget_name?)

    errors.add(:base, LP_UNSAFE_MESSAGE) unless self.class.lp_safe_widget_names(entity).include?(widget_name)
  end

  # C1 — metadata must be a plain {key: value} literal. Checked only when metadata changes, so the
  # form, the xlsx import, starter layouts and seeds all get a clear error instead of a stored expression.
  def metadata_must_be_literal
    # C1-1 / C1-3 — an expression ({title: 6 * 7}) is refused for GP and LP users alike;
    # C1-X5 — on import the row fails with this message and the other rows still save
    RubyLiteral.parse_hash(metadata)
  rescue RubyLiteral::NotLiteral => e
    errors.add(:metadata, "#{METADATA_LITERAL_MESSAGE} (#{e.message})")
  end

  def extract_keys_from_help
    keys = {}.deep_symbolize_keys
    # Match key: value where value can be a quoted string, an array [...], or a simple value
    # This is still a heuristic but better than the previous one
    metadata_help.scan(/(\w+):\s*('[^']*'|"[^"]*"|\[[^\]]*\]|[^,{}]+)/).each do |key, value|
      clean_value = value.strip
      # If it's a quoted string, strip quotes for the internal representation
      if (clean_value.start_with?("'") && clean_value.end_with?("'")) ||
         (clean_value.start_with?('"') && clean_value.end_with?('"'))
        clean_value = clean_value[1...-1]
      end
      # Remove trailing dots and commas that are often used in help text
      clean_value = clean_value.gsub(/\.\.\.*/, "").gsub(/,\s*$/, "").strip
      keys[key] = clean_value
    end
    keys
  rescue StandardError
    {}.deep_symbolize_keys
  end
end
