class CallFee < ApplicationRecord
  belongs_to :entity
  belongs_to :fund
  belongs_to :capital_call
  validates :name, :start_date, :end_date, :fee_type, presence: true

  NESTED_ATTRIBUTES = %i[id name start_date end_date fee_type notes _destroy].freeze
  NESTED_ATTRIBUTES_WITH_FORMULA = %i[id name start_date end_date fee_type notes _destroy formula].freeze

  before_validation :setup_entity

  scope :formulas, -> { where(formula: true) }

  def setup_entity
    self.entity_id = capital_call.entity_id
    self.fund_id = capital_call.fund_id
  end

  # This is used to calculate the fee based on the formula in the notes
  # Should return the amount in cents
  def calculate_formula(capital_remittance)
    capital_call = self.capital_call
    capital_commitment = capital_remittance.capital_commitment
    eval(notes, binding)
  end
end
