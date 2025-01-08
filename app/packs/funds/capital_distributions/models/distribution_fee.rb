class DistributionFee < ApplicationRecord
  belongs_to :entity
  belongs_to :fund
  belongs_to :capital_distribution
  validates :name, :start_date, :end_date, presence: true

  TYPES = ["FV For Redemption", "Income", "Expense", "Tax", "Reinvestment"].freeze

  NESTED_ATTRIBUTES = %i[id name start_date end_date fee_type notes _destroy].freeze
  NESTED_ATTRIBUTES_WITH_FORMULA = %i[id name start_date end_date fee_type notes _destroy formula].freeze

  before_validation :setup_entity

  scope :formulas, -> { where(formula: true) }

  def setup_entity
    self.entity_id = capital_distribution.entity_id
    self.fund_id = capital_distribution.fund_id
  end

  # This is used to calculate the fee based on the formula in the notes
  # Should return the amount in cents
  def calculate_formula(capital_remittance)
    capital_distribution = self.capital_distribution
    capital_commitment = capital_distribution.capital_commitment
    eval(notes, binding)
  end
end
