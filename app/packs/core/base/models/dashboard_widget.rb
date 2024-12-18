class DashboardWidget < ApplicationRecord
  acts_as_list scope: %i[owner dashboard_name]
  belongs_to :entity
  belongs_to :owner, polymorphic: true, optional: true

  validates :dashboard_name, :widget_name, :size, :tags, presence: true

  scope :enabled, -> { where(enabled: true) }
  attr_accessor :path

  FUND_WIDGETS = [
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Ratios", path: "funds/widgets/fund_ratios", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Cashflows", path: "funds/widgets/fund_cashflows", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Distributions", path: "funds/widgets/fund_distributions", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Account Entries", path: "funds/widgets/fund_account_entries", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Portfolios", path: "funds/widgets/fund_portfolios", size: "Large")
  ].freeze

  OPS_WIDGETS = [
    DashboardWidget.new(dashboard_name: "Ops Dashboard", widget_name: "Ops: My Tasks", path: "dashboard_widgets/widgets/my_tasks", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Ops Dashboard", widget_name: "Ops: Upcoming Events", path: "dashboard_widgets/widgets/events", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Ops Dashboard", widget_name: "Ops: Investors No Interaction", path:
    "dashboard_widgets/widgets/investors_no_interaction", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Ops Dashboard", widget_name: "Ops: Notes", path: "dashboard_widgets/widgets/notes", size: "Medium")
  ].freeze

  WIDGETS = {
    "Fund Dashboard" => FUND_WIDGETS,
    "Ops Dashboard" => OPS_WIDGETS
  }.freeze

  def to_s
    "#{dashboard_name} #{widget_name} #{tags}"
  end

  # rubocop:disable Security/Eval
  def metadata_args
    eval(metadata) if metadata
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
