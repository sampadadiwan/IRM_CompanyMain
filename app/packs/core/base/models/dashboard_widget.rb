class DashboardWidget < ApplicationRecord
  acts_as_list scope: %i[owner dashboard_name]
  belongs_to :entity
  belongs_to :owner, polymorphic: true, optional: true

  validates :dashboard_name, :widget_name, :size, :tags, presence: true

  scope :enabled, -> { where(enabled: true) }
  attr_accessor :path

  FUND_WIDGETS = [
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Stats", path: "funds/stats", size: "Large"),
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Card", path: "funds/card", size: "Large"),
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Ratios", path: "funds/widgets/fund_ratios", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Cashflows", path: "funds/widgets/fund_cashflows", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Distributions", path: "funds/widgets/fund_distributions", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Account Entries", path: "funds/widgets/fund_account_entries", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Portfolios", path: "aggregate_portfolio_investments/widgets/portfolio_investments", size: "XL")

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
    DashboardWidget.new(dashboard_name: "Investor Dashboard", widget_name: "Commitments", path: "investors/widgets/commitments", size: "Medium")

  ].freeze

  PORTFOLIO_COMPANY_WIDGETS = [

    DashboardWidget.new(dashboard_name: "Portfolio Company Dashboard", widget_name: "Valuations", path: "investors/widgets/valuations", size: "XL"),
    DashboardWidget.new(dashboard_name: "Portfolio Company Dashboard", widget_name: "Portfolio Company Fund Ratios", path: "investors/widgets/fund_ratios", size: "XL"),
    DashboardWidget.new(dashboard_name: "Portfolio Company Dashboard", widget_name: "Portfolio Company KPIs", path: "investors/widgets/kpis_grid_view", size: "XL"),
    DashboardWidget.new(dashboard_name: "Portfolio Company Dashboard", widget_name: "Documents", path: "investors/widgets/documents", size: "XL"),
    DashboardWidget.new(dashboard_name: "Portfolio Company Dashboard", widget_name: "My Tasks", path: "dashboard_widgets/widgets/my_tasks", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Portfolio Company Dashboard", widget_name: "Upcoming Events", path: "dashboard_widgets/widgets/events", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Portfolio Company Dashboard", widget_name: "Notes", path: "dashboard_widgets/widgets/notes", size: "Medium")

  ].freeze

  PORTFOLIO_WIDGETS = [
    DashboardWidget.new(dashboard_name: "Portfolio Dashboard", widget_name: "Portfolio Stats", path: "aggregate_portfolio_investments/widgets/stats", size: "XL"),
    DashboardWidget.new(dashboard_name: "Portfolio Dashboard", widget_name: "Portfolio Investments", path: "aggregate_portfolio_investments/widgets/portfolio_investments", size: "XL"),
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
end
