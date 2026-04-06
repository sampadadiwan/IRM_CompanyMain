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
    "For; text-col" => "owner_name; text-col",
    "Type; text-col" => "owner_type; text-col",
    "Name; text-col" => "name; text-col",
    "Display Value; num-col" => "display_value; num-col",
    "On; date-col" => "end_date; date-col",
    "Scenario; text-col" => "scenario; text-col"
  }.freeze

  ADDITIONAL_COLUMNS_FROM = ["fund"].freeze

  CONDENSED_COLUMNS = {
    "Name; text-col" => "name; text-col",
    "Display Value; num-col" => "display_value; num-col",
    "On; date-col" => "end_date; date-col"
  }.freeze

  validates :display_value, :label, length: { maximum: 50 }
  validates :name, :owner_type, length: { maximum: 255 }

  scope :latest, -> { where(latest: true) }
  scope :default, -> { where(scenario: "Default") }
  scope :for_portfolio_companies, -> { where(owner_type: "PortfolioCompany") }

  before_create :set_scenario_if_missing
  def set_scenario_if_missing
    self.scenario = portfolio_scenario.name if (scenario.blank? || scenario == "Default") && portfolio_scenario.present?
  end

  def to_s
    "#{name} #{value}"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name value owner_type owner_id end_date latest fund_id scenario].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[fund portfolio_scenario]
  end
end
