class PortfolioScenario < ApplicationRecord
  include ForInvestor

  belongs_to :entity
  belongs_to :fund
  attr_readonly :fund_id # never moves to another fund (funds_api_security_policy_plan.md, B)
  belongs_to :user

  serialize :calculations, type: Hash

  has_many :scenario_investments, dependent: :destroy
  # Polymorphic child side — destroy ratios when the scenario is deleted (they are
  # meaningless without the scenario context, unlike FundRatioRun which nullifies).
  has_many :fund_ratios, as: :computation_context, dependent: :destroy

  validates :name, presence: true, length: { maximum: 100 }

  def to_s
    name
  end

  after_update :broadcast
  def broadcast
    broadcast_replace_to ["portfolio_scenario_#{id}"],
                         partial: '/portfolio_scenarios/show',
                         locals: { portfolio_scenario: self },
                         target: "portfolio_scenario_#{id}"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name updated_at]
  end
end
