class FundRatio < ApplicationRecord
  # include Trackable.new
  include ForInvestor

  belongs_to :entity
  belongs_to :fund
  belongs_to :capital_commitment, optional: true
  belongs_to :valuation, optional: true
  belongs_to :owner, polymorphic: true, optional: true
  belongs_to :portfolio_scenario, optional: true

  STANDARD_COLUMNS = {
    "For" => "owner_name",
    "Type" => "owner_type",
    "Name" => "name",
    "Display Value" => "display_value",
    "On" => "end_date",
    "Scenario" => "scenario"
  }.freeze

  ADDITIONAL_COLUMNS_FROM = ["fund"].freeze

  CONDENSED_COLUMNS = {
    "Name" => "name",
    "Display Value" => "display_value",
    "On" => "end_date"
  }.freeze

  validates :display_value, :label, length: { maximum: 50 }
  validates :name, :owner_type, length: { maximum: 255 }

  scope :latest, -> { where(latest: true) }
  scope :default, -> { where(scenario: "Default") }

  def to_s
    "#{name} #{value}"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name value notes owner_type owner_id end_date latest portfolio_scenario_id portfolio_scenario_name].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[fund portfolio_scenario]
  end
end
