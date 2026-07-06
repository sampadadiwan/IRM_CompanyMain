class DistributionFee < ApplicationRecord
  belongs_to :entity
  belongs_to :fund
  belongs_to :capital_distribution
  validates :start_date, :end_date, presence: true
  # if name is blank we need entry type to filter
  # we need either name or audit name to create audit
  validates :audit_name, :entry_type, presence: true, if: ->(fee) { fee.name.blank? }
  validates :name, :audit_name, length: { maximum: 65 }, allow_blank: true
  validates :fee_type, length: { maximum: 20 }, allow_blank: true

  TYPES = ["FV For Redemption", "Income", "Expense", "Tax", "Reinvestment", "Display Only"].freeze

  # Maps each fee type label to the context key suffix used when storing breakdowns.
  # Used in CapitalDistributionPaymentDocGenerator
  KYC_FEE_TYPE_KEYS = {
    "FV For Redemption" => :fvr,
    "Income" => :income,
    "Expense" => :expense,
    "Tax" => :tax,
    "Reinvestment" => :reinvestment,
    "Display Only" => :disp
  }.freeze

  NESTED_ATTRIBUTES = %i[id name start_date end_date fee_type notes _destroy].freeze
  NESTED_ATTRIBUTES_WITH_FORMULA = %i[id name start_date end_date fee_type notes _destroy formula].freeze

  before_validation :setup_entity

  scope :formulas, -> { where(formula: true) }
  scope :income, -> { where(fee_type: "Income") }
  scope :expense, -> { where(fee_type: "Expense") }
  scope :tax, -> { where(fee_type: "Tax") }
  scope :reinvestment, -> { where(fee_type: "Reinvestment") }
  scope :display_only, -> { where(fee_type: "Display Only") }
  scope :fv_for_redemption, -> { where(fee_type: "FV For Redemption") }

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
