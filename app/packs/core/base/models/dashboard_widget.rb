class DashboardWidget < ApplicationRecord
  acts_as_list scope: :owner
  belongs_to :entity
  belongs_to :owner, polymorphic: true, optional: true

  scope :enabled, -> { where(enabled: true) }
  attr_accessor :path

  FUND_WIDGETS = [
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Ratios", path: "funds/widgets/fund_ratios", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Cashflows", path: "funds/widgets/fund_cashflows", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Distributions", path: "funds/widgets/fund_distributions", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Account Entries", path: "funds/widgets/fund_account_entries", size: "Medium"),
    DashboardWidget.new(dashboard_name: "Fund Dashboard", widget_name: "Fund Portfolios", path: "funds/widgets/fund_portfolios", size: "Large")
  ].freeze

  WIDGETS = {
    "Fund Dashboard" => FUND_WIDGETS
  }.freeze

  def to_s
    "#{dashboard_name} #{widget_name} #{tags}"
  end

  def metadata_args
    eval(metadata) if metadata
  end

  def widget_size
    case size
    when "Small"
      "col-md-4"
    when "Medium"
      "col-md-6"
    when "Large"
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
end
