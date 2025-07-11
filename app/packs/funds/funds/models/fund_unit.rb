class FundUnit < ApplicationRecord
  include ForInvestor
  include Trackable.new

  belongs_to :entity
  belongs_to :fund
  belongs_to :capital_commitment
  belongs_to :investor
  belongs_to :owner, polymorphic: true, optional: true

  validates :unit_type, length: { maximum: 40 }
  validates :owner_type, length: { maximum: 255 }

  monetize :total_premium_cents, :amount_cents, :price_cents, :premium_cents, with_currency: ->(i) { i.fund.currency }

  counter_culture :owner, column_name: 'units_quantity', delta_column: 'quantity'

  counter_culture :capital_commitment, column_name: 'total_fund_units_quantity', delta_column: 'quantity'

  counter_culture :capital_commitment, column_name: 'total_units_premium_cents', delta_column: 'total_premium_cents'

  # Rollup the total amount of all units for the capital commitment but only if the amount_cents is positive, ie dont rollup the distributions and transfer out. Used in CapitalCommitment.units_amount_minus_collected
  counter_culture :capital_commitment, column_name: proc { |r| r.amount_cents.positive? ? 'total_units_amount_cents' : nil },
                                       delta_column: "amount_cents",
                                       column_names: {
                                         ["fund_units.amount_cents > 0"] => 'total_units_amount_cents'
                                       },
                                       execute_after_commit: true

  counter_culture :fund, column_name: 'total_units_premium_cents', delta_column: "total_premium_cents"

  scope :for_remittances, -> { where(owner_type: 'CapitalRemittance') }
  scope :for_distributions, -> { where(owner_type: 'CapitalDistribution') }

  def to_s
    unit_type
  end

  before_save :calculate_amount_cents
  def calculate_amount_cents
    self.amount_cents = quantity * (price_cents + premium_cents)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[issue_date premium price quantity reason unit_type].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[capital_commitment investor]
  end
end
