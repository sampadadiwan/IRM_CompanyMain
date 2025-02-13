class ExcusedInvestor < ApplicationRecord
  include ForInvestor

  belongs_to :entity
  belongs_to :fund

  # The investor / folio that is excused
  belongs_to :capital_commitment

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
end
