class DashboardWidget < ApplicationRecord
  acts_as_list scope: %i[owner dashboard_name entity_id]
  belongs_to :entity
  belongs_to :owner, polymorphic: true, optional: true

  validates :dashboard_name, :widget_name, :size, :tags, presence: true

  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :for_dashboard, ->(dashboard_name) { where(dashboard_name: dashboard_name) }
  scope :widget_name, ->(widget_name) { where(widget_name: widget_name) }
  scope :with_size, ->(size) { where(size: size) }

  # The path to the widget partial to be rendered
  attr_accessor :path
  # metadata help text to be show in the UI, to help users understand what metadata can be passed
  attr_accessor :metadata_help

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
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Fund Ratios", path: "funds/widgets/fund_ratios", size: "Medium", metadata_help: "{title: 'Title', scenario: 'Default', condensed: true, chart: false, list: true, months: 12, ratio_names: ['XIRR', 'TVPI', 'DPI' ....] }"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Fund Cashflows", path: "funds/widgets/fund_cashflows", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Fund Distributions", path: "funds/widgets/fund_distributions", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Fund Account Entries", path: "funds/widgets/fund_account_entries", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Fund Portfolios", path: "aggregate_portfolio_investments/widgets/portfolio_investments", size: "XL"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Fund Portfolio Stats", path: "aggregate_portfolio_investments/widgets/stats", size: "XL", metadata_help: "{fields: 'Bought Amount,Sold Amount,...', force_units: 'Lakhs/Crores/Millions'}"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Fund Report", path: "funds/widgets/fund_report", size: "XL", metadata_help: "{report_id: 1, other_report_args: '...' }"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Embed Document", path: "funds/widgets/embedded_doc", size: "XL", metadata_help: "{name: 'Document Name'}"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Commitment Deployment", path: "capital_commitments/widgets/deployment", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Investor Concentration", path: "capital_commitments/widgets/investor_concentration", size: "Medium", metadata_help: "{top_n: 10}"),
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
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Remittance Timeline", path: "capital_remittances/widgets/payment_timeline", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Portfolio Allocation", path: "aggregate_portfolio_investments/widgets/allocation", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Investment Performance", path: "aggregate_portfolio_investments/widgets/performance", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Realized vs Unrealized", path: "aggregate_portfolio_investments/widgets/gain_breakdown", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Instrument Exposure", path: "aggregate_portfolio_investments/widgets/instrument_exposure", size: "Medium"),
    DashboardWidget.new(dashboard_name: FUND_DASHBOARD, widget_name: "Portfolio Income", path: "aggregate_portfolio_investments/widgets/income_by_company", size: "Medium"),
    DashboardWidget.new(dashboard_name: LP_LANDING_PAGE, widget_name: "Account Entries Chart", path: "capital_commitments/widgets/account_entries_chart", size: "Medium", metadata_help: "{account_entry_names: 'Management Fee, Setup Fee', chart_type: 'column/pie/line', aggregate_by: 'quarter/year/sum', number_of_periods: 8}")
  ].freeze

  OPS_WIDGETS = [
    DashboardWidget.new(dashboard_name: OPS_DASHBOARD, widget_name: "My Tasks", path: "dashboard_widgets/widgets/my_tasks", size: "Medium"),
    DashboardWidget.new(dashboard_name: OPS_DASHBOARD, widget_name: "Upcoming Events", path: "dashboard_widgets/widgets/events", size: "Medium"),
    DashboardWidget.new(dashboard_name: OPS_DASHBOARD, widget_name: "Investors No Interaction", path:
    "dashboard_widgets/widgets/investors_no_interaction", size: "Medium"),
    DashboardWidget.new(dashboard_name: OPS_DASHBOARD, widget_name: "Notes", path: "dashboard_widgets/widgets/notes", size: "Medium")
  ].freeze

  INVESTOR_WIDGETS = [

    DashboardWidget.new(dashboard_name: INVESTOR_DASHBOARD, widget_name: "Documents", path: "investors/widgets/documents", size: "XL", metadata_help: "{owner_type: 'Investor'/'Valuation', owner_id: 123, folder_id:, include_sub_folders: false, card_view: true, per_page: 6, per_row: 3, show_owner: false, show_tags: false}"),
    DashboardWidget.new(dashboard_name: INVESTOR_DASHBOARD, widget_name: "My Tasks", path: "dashboard_widgets/widgets/my_tasks", size: "Medium"),
    DashboardWidget.new(dashboard_name: INVESTOR_DASHBOARD, widget_name: "Upcoming Events", path: "dashboard_widgets/widgets/events", size: "Medium"),
    DashboardWidget.new(dashboard_name: INVESTOR_DASHBOARD, widget_name: "Notes", path: "dashboard_widgets/widgets/notes", size: "Medium"),
    DashboardWidget.new(dashboard_name: INVESTOR_DASHBOARD, widget_name: "KYCs", path: "investors/widgets/kycs", size: "Medium"),
    DashboardWidget.new(dashboard_name: INVESTOR_DASHBOARD, widget_name: "Commitments", path: "investors/widgets/commitments", size: "Medium"),
    DashboardWidget.new(dashboard_name: INVESTOR_DASHBOARD, widget_name: "Embed Document", path: "investors/widgets/embedded_doc", size: "XL", metadata_help: "{name: 'Document Name'}")

  ].freeze

  PORTFOLIO_COMPANY_WIDGETS = [

    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Valuations", path: "investors/widgets/valuations", size: "XL"),

    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Fund Ratios", path: "investors/widgets/fund_ratios", size: "XL", metadata_help: "{title: 'Title', scenarios: true, show_currency_filter:true, condensed: true, chart: false, list: true, months: 12, ratio_names: ['XIRR', 'TVPI', 'DPI' ....]}"),

    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Kpis", path: "investors/widgets/kpis_grid_view", size: "XL", metadata_help: "{title_suffix: 'Title Suffix', chart: false, tag_list: 'Actual,Budget', show_tags: false, compound: false, period: 'Quarter', no_of_periods: 12, no_actions: false, categories: 'Balance Sheet, Income Statement', force_units: 'Lakhs/Crores/Millions', decimals: 2, show_chart: true, show_table: true}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Kpis Performance Table", path: "investors/widgets/performance_table", size: "XL", metadata_help: "{chart: false}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Kpis Budget vs Actual", path: "investors/widgets/kpis_budget_vs_actual", size: "XL", metadata_help: "{categories: 'Income Statement', category: 'IC P/L (INR Mn)', tag_list: 'Actual,Budget', units: 'Lakhs', num_periods: 2, period: 'Year', decimals: 1}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Data Card", path: "investors/widgets/data_card", size: "XL", metadata_help: '{cols: 1, fields: "Category:category,City:city,Sector:custom_fields.sector,Founder:custom_fields.founder"}'),

    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Portfolio Investments", path: "aggregate_portfolio_investments/widgets/portfolio_investments", size: "XL", metadata_help: "{ag: true, group_by_column: 'investment_instrument_name', show_fund_name: true}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Documents", path: "investors/widgets/documents", size: "XL", metadata_help: "{owner_type: 'Investor'/'Valuation', owner_id: 123, folder_id: 123, include_sub_folders: false, card_view: true, per_page: 6, per_row: 3, show_owner: false, show_tags: false}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "My Tasks", path: "dashboard_widgets/widgets/my_tasks", size: "Medium"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Upcoming Events", path: "dashboard_widgets/widgets/events", size: "Medium"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Notes", path: "dashboard_widgets/widgets/notes", size: "XL"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Value Bridge", path: "investors/widgets/value_bridge", size: "XL", metadata_help: "{instruments: 'All or Specified in stakeholder custom field called value_bridge_instruments', across: 'First Last or Last 2', show_form: true, hide_table: false}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Captable", path: "investments/widgets/captable", size: "XL", metadata_help: "{show_charts: true, diluted_chart: 'pie/donut/half_donut', custom_colors: false, show_investments: false, show_captable: true, self_by_funding_round: true, amount_by_funding_round: true, diluted_share_holdings: true, amount_by_investor: true, each_funding_round: false, show_quantity_actual: false, show_quantity_diluted: false}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Portfolio Company Report", path: "funds/widgets/fund_report", size: "XL", metadata_help: "{report_id: 1, title: 'Valuations', show_prefix: false, show_name: true, show_inputs: false, show_tags: true, show_instrument: false, other_report_args: '...' }"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Portfolio Report", path: "investors/widgets/portfolio_report", size: "XL", metadata_help: "{tabs: 'Tab1, Tab2', portfolio_report_id: 123}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, widget_name: "Key Kpis", path: "investors/widgets/kpi_key_numbers", size: "XL", metadata_help: "{kpis: 'csv of kpi names to show'}"),

    DashboardWidget.new(dashboard_name: PORTFOLIO_DASHBOARD, widget_name: "Portfolio Stats", path: "aggregate_portfolio_investments/widgets/stats", size: "XL", metadata_help: "{fields: 'Bought Amount,Sold Amount,...', field_names: 'Bought, Sold,...', force_units: 'Lakhs/Crores/Millions', tracking_currency: true}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_DASHBOARD, widget_name: "Embed Document", path: "investors/widgets/embedded_doc", size: "XL", metadata_help: "{name: 'Document Name', xlsx_as_grid: true/false}"),

    DashboardWidget.new(dashboard_name: PORTFOLIO_DASHBOARD, widget_name: "Agent Chart", path: "investors/widgets/agent_chart", size: "XL", metadata_help: "{title: 'Chart Title'}")

  ].freeze

  PORTFOLIO_WIDGETS = [
    DashboardWidget.new(dashboard_name: PORTFOLIO_DASHBOARD, widget_name: "Portfolio Stats", path: "aggregate_portfolio_investments/widgets/stats", size: "XL", metadata_help: "{fields: 'Bought Amount,Sold Amount,...', force_units: 'Lakhs/Crores/Millions'}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_DASHBOARD, widget_name: "Portfolio Investments", path: "aggregate_portfolio_investments/widgets/portfolio_investments", size: "XL", metadata_help: "{ag: true, group_by_column: 'investment_instrument_name', show_fund_name: true/false}"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_DASHBOARD, widget_name: "FMV %", path: "aggregate_portfolio_investments/widgets/fmv_percentage", size: "Medium"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_DASHBOARD, widget_name: "Holding Cost %", path: "aggregate_portfolio_investments/widgets/holding_costs_percentage", size: "Medium"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_DASHBOARD, widget_name: "Bought %", path: "aggregate_portfolio_investments/widgets/bought_percentage", size: "Medium"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_DASHBOARD, widget_name: "Sold %", path: "aggregate_portfolio_investments/widgets/sold_percentage", size: "Medium"),
    DashboardWidget.new(dashboard_name: PORTFOLIO_DASHBOARD, widget_name: "Portfolio IRR", path: "aggregate_portfolio_investments/widgets/irr", size: "XL", metadata_help: "{show_table: false, show_chart: false}")
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
      metadata_help: "{title: 'Stats', decimals: 3, currency: 'INR', force_units: 'Lakhs'}"
    ),
    DashboardWidget.new(dashboard_name: AGGREGATED_PORTFOLIO_DASHBOARD, widget_name: "Company Charts", path: "aggregate_portfolio_investments/widgets/portfolio_company_charts", size: "XL", metadata_help: "{show_sector_wise: true, show_portfolio_company_wise: true , show_table: false, show_chart:true, plot: 'bought_amount', table_limit: 8, title: 'FMV by Company'}", position: 4),
    DashboardWidget.new(dashboard_name: AGGREGATED_PORTFOLIO_DASHBOARD, widget_name: "Fund Ratios", path: "aggregate_portfolio_investments/widgets/fund_ratio_aggregate", size: "XL", metadata_help: "{show_table: true, show_chart: true, ratio_names: ['Gross Portfolio IRR', 'Gross Portfolio MOIC'], titles: ['IRR', 'MOIC'], chart_colors: ['green', 'DarkOrange']}"),
    DashboardWidget.new(dashboard_name: AGGREGATED_PORTFOLIO_DASHBOARD, widget_name: "Company Ratios", path: "aggregate_portfolio_investments/widgets/company_ratios_aggregate", size: "XL", metadata_help: "{show_table: true, show_chart: true, ratio_names: ['IRR', 'MOIC'], titles: ['IRR', 'MOIC'], chart_colors: ['green', 'DarkOrange'], negative_colors:['orange', 'red']}")

  ].freeze

  FM_LANDING_PAGE_WIDGETS = [
    DashboardWidget.new(dashboard_name: FM_LANDING_PAGE, widget_name: "FM Stats", path: "entities/widgets/fm_stats", size: "XL"),
    DashboardWidget.new(dashboard_name: FM_LANDING_PAGE, widget_name: "Funds", path: "entities/widgets/funds", size: "XL"),
    DashboardWidget.new(dashboard_name: FM_LANDING_PAGE, widget_name: "Investment Opportunities", path: "entities/widgets/investment_opportunities", size: "XL")
  ].freeze

  LP_LANDING_PAGE_WIDGETS = [
    DashboardWidget.new(dashboard_name: LP_LANDING_PAGE, widget_name: "Funds", path: "entities/widgets/lp_funds", size: "XL"),
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

  def to_s
    "#{dashboard_name} #{widget_name} #{tags} #{tag_list}"
  end

  # rubocop:disable Security/Eval
  def metadata_args
    ret_val = metadata ? eval(metadata) : {}
    ret_val.is_a?(Hash) ? ret_val : {}
  end
  # rubocop:enable Security/Eval

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
    %w[enabled dashboard_name widget_name owner_type position tags tag_list]
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

  def self.widget_select
    WIDGETS.transform_values do |widgets|
      widgets.map(&:widget_name).sort
    end
  end
end
