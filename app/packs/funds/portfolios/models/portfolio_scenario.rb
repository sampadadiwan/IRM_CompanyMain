class PortfolioScenario < ApplicationRecord
  include ForInvestor

  belongs_to :entity
  belongs_to :fund
  belongs_to :user

  serialize :calculations, type: Hash

  has_many :scenario_investments, dependent: :destroy

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
end
