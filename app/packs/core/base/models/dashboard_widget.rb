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

  FUND_WIDGETS = [
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Stats", path: "funds/stats", size: "XL"),
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Card", path: "funds/card", size: "XL"),
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Ratios", path: "funds/widgets/fund_ratios", size: "Medium", metadata_help: "{scenario: 'Default', months: 12, ratio_names: ['XIRR', 'TVPI', 'DPI' ....] }"),
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Cashflows", path: "funds/widgets/fund_cashflows", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Distributions", path: "funds/widgets/fund_distributions", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Account Entries", path: "funds/widgets/fund_account_entries", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Portfolios", path: "aggregate_portfolio_investments/widgets/portfolio_investments", size: "XL"),
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Portfolio Stats", path: "aggregate_portfolio_investments/widgets/stats", size: "XL", metadata_help: "{fields: 'Bought Amount,Sold Amount,...', force_units: 'Lakhs/Crores/Millions'}"),
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Report", path: "funds/widgets/fund_report", size: "XL", metadata_help: "{report_id: 1, other_report_args: '...' }"),
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Embed Document", path: "funds/widgets/embedded_doc", size: "XL", metadata_help: "{name: 'Document Name'}")

  ].freeze

  OPS_WIDGETS = [
    DashboardWidget.new(dashboard_name: "Ops Dashboard", widget_name: "My Tasks", path: "dashboard_widgets/widgets/my_tasks", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Ops Dashboard", widget_name: "Upcoming Events", path: "dashboard_widgets/widgets/events", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Ops Dashboard", widget_name: "Investors No Interaction", path:
    "dashboard_widgets/widgets/investors_no_interaction", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Ops Dashboard", widget_name: "Notes", path: "dashboard_widgets/widgets/notes", size: "Medium")
  ].freeze

  INVESTOR_WIDGETS = [

    DashboardWidget.new(dashboard_name: "Investor Dashboard", widget_name: "Documents", path: "investors/widgets/documents", size: "XL"),
    DashboardWidget.new(dashboard_name: "Investor Dashboard", widget_name: "My Tasks", path: "dashboard_widgets/widgets/my_tasks", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Investor Dashboard", widget_name: "Upcoming Events", path: "dashboard_widgets/widgets/events", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Investor Dashboard", widget_name: "Notes", path: "dashboard_widgets/widgets/notes", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Investor Dashboard", widget_name: "KYCs", path: "investors/widgets/kycs", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Investor Dashboard", widget_name: "Commitments", path: "investors/widgets/commitments", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Investor Dashboard", widget_name: "Embed Document", path: "investors/widgets/embedded_doc", size: "XL", metadata_help: "{name: 'Document Name'}")

  ].freeze

  PORTFOLIO_COMPANY_WIDGETS = [

    DashboardWidget.new(dashboard_name: "Portfolio Company Dashboard", widget_name: "Valuations", path: "investors/widgets/valuations", size: "XL"),

    DashboardWidget.new(dashboard_name: "Portfolio Company Dashboard", widget_name: "Fund Ratios", path: "investors/widgets/fund_ratios", size: "XL", metadata_help: "{scenario: 'Default', condensed: true, chart: false, list: true, months: 12, ratio_names: ['XIRR', 'TVPI', 'DPI' ....]}"),

    DashboardWidget.new(dashboard_name: "Portfolio Company Dashboard", widget_name: "Kpis", path: "investors/widgets/kpis_grid_view", size: "XL", metadata_help: "{chart: false, compound: false, period: 'Quarter', no_actions: false, categories: 'Balance Sheet, Income Statement', force_units: 'Lakhs/Crores/Millions'}"),
    DashboardWidget.new(dashboard_name: "Portfolio Company Dashboard", widget_name: "Kpis Performance Table", path: "investors/widgets/performance_table", size: "XL", metadata_help: "{chart: false}"),
    DashboardWidget.new(dashboard_name: "Portfolio Company Dashboard", widget_name: "Kpis Budget vs Actual", path: "investors/widgets/kpis_budget_vs_actual", size: "XL", metadata_help: "{categories: 'Income Statement', tag_list: 'Actual,Budget', units: 'Lakhs', num_periods: 2}"),

    DashboardWidget.new(dashboard_name: "Portfolio Company Dashboard", widget_name: "Data Card", path: "investors/widgets/data_card", size: "XL", metadata_help: '{cols: 1, fields: "Category:category,City:city,Sector:custom_fields.sector,Founder:custom_fields.founder"}'),

    DashboardWidget.new(dashboard_name: "Portfolio Company Dashboard", widget_name: "Portfolio Investments", path: "aggregate_portfolio_investments/widgets/portfolio_investments", size: "XL", metadata_help: "{ag: true, group_by_column: 'investment_instrument_name', show_fund_name: true}"),
    DashboardWidget.new(dashboard_name: "Portfolio Company Dashboard", widget_name: "Documents", path: "investors/widgets/documents", size: "XL"),
    DashboardWidget.new(dashboard_name: "Portfolio Company Dashboard", widget_name: "My Tasks", path: "dashboard_widgets/widgets/my_tasks", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Portfolio Company Dashboard", widget_name: "Upcoming Events", path: "dashboard_widgets/widgets/events", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Portfolio Company Dashboard", widget_name: "Notes", path: "dashboard_widgets/widgets/notes", size: "XL"),
    DashboardWidget.new(dashboard_name: "Portfolio Company Dashboard", widget_name: "Value Bridge", path: "investors/widgets/value_bridge", size: "XL", metadata_help: "{instruments: 'All or Specified in stakeholder custom field called value_bridge_instruments', across: 'First Last or Last 2', show_form: true}"),
    DashboardWidget.new(dashboard_name: "Portfolio Company Dashboard", widget_name: "Captable", path: "investments/widgets/captable", size: "XL", metadata_help: "{show_charts: true, show_investments: false, show_captable: true, self_by_funding_round: true, amount_by_funding_round: true, diluted_share_holdings: true, amount_by_investor: true, each_funding_round: false}"),
    DashboardWidget.new(dashboard_name: "Portfolio Company Dashboard", widget_name: "Portfolio Company Report", path: "funds/widgets/fund_report", size: "XL", metadata_help: "{report_id: 1, other_report_args: '...' }"),
    DashboardWidget.new(dashboard_name: "Portfolio Company Dashboard", widget_name: "Portfolio Report", path: "investors/widgets/portfolio_report", size: "XL"),
    DashboardWidget.new(dashboard_name: "Portfolio Company Dashboard", widget_name: "Key Kpis", path: "investors/widgets/kpi_key_numbers", size: "XL", metadata_help: "{kpis: 'csv of kpi names to show'}"),

    DashboardWidget.new(dashboard_name: "Portfolio Dashboard", widget_name: "Portfolio Stats", path: "aggregate_portfolio_investments/widgets/stats", size: "XL", metadata_help: "{fields: 'Bought Amount,Sold Amount,...', force_units: 'Lakhs/Crores/Millions'}"),
    DashboardWidget.new(dashboard_name: "Portfolio Dashboard", widget_name: "Embed Document", path: "investors/widgets/embedded_doc", size: "XL", metadata_help: "{name: 'Document Name'}")

  ].freeze

  PORTFOLIO_WIDGETS = [
    DashboardWidget.new(dashboard_name: "Portfolio Dashboard", widget_name: "Portfolio Stats", path: "aggregate_portfolio_investments/widgets/stats", size: "XL", metadata_help: "{fields: 'Bought Amount,Sold Amount,...', force_units: 'Lakhs/Crores/Millions'}"),
    DashboardWidget.new(dashboard_name: "Portfolio Dashboard", widget_name: "Portfolio Investments", path: "aggregate_portfolio_investments/widgets/portfolio_investments", size: "XL", metadata_help: "{ag: true, group_by_column: 'investment_instrument_name', show_fund_name: true/false}"),
    DashboardWidget.new(dashboard_name: "Portfolio Dashboard", widget_name: "FMV %", path: "aggregate_portfolio_investments/widgets/fmv_percentage", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Portfolio Dashboard", widget_name: "Holding Cost %", path: "aggregate_portfolio_investments/widgets/holding_costs_percentage", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Portfolio Dashboard", widget_name: "Bought %", path: "aggregate_portfolio_investments/widgets/bought_percentage", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Portfolio Dashboard", widget_name: "Sold %", path: "aggregate_portfolio_investments/widgets/sold_percentage", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Portfolio Dashboard", widget_name: "Portfolio IRR", path: "aggregate_portfolio_investments/widgets/irr", size: "XL")
  ].freeze

  WIDGETS = {
    "Fund Dashboard" => FUND_WIDGETS,
    "Ops Dashboard" => OPS_WIDGETS,
    "Investor Dashboard" => INVESTOR_WIDGETS,
    "Portfolio Company Dashboard" => PORTFOLIO_COMPANY_WIDGETS,
    "Portfolio Dashboard" => PORTFOLIO_WIDGETS
  }.freeze

  def to_s
    "#{dashboard_name} #{widget_name} #{tags}"
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
      "col-md-9"
    when "XL"
      "col-md-12"
    else
      "col"
    end
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[enabled dashboard_name widget_name owner_type position tags]
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
