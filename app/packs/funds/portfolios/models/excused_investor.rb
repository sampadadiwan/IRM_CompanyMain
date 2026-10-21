class ExcusedInvestor < ApplicationRecord
  include ForInvestor

  belongs_to :entity
  belongs_to :fund
  attr_readonly :fund_id # never moves to another fund (funds_api_security_policy_plan.md, B)

  # The investor / folio that is excused
  belongs_to :capital_commitment
  # Exposes investor for policy entity-scoping (permissioned_investor? checks record.investor)
  delegate :investor, to: :capital_commitment

  # Excused from either all investments in the portfolio_company
  belongs_to :portfolio_company, class_name: "Investor", optional: true
  # Or excused from a portfolio_company / instrument
  belongs_to :aggregate_portfolio_investment, optional: true
  # Or from a specific investment
  belongs_to :portfolio_investment, optional: true

  def to_s
    "#{fund}: #{capital_commitment}"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[created_at notes]
  end

  # No association is searchable; Ransack 6 asks for this list on any non-column condition and raises without it
  def self.ransackable_associations(_auth_object = nil)
    []
  end
end
