class FundUnit < ApplicationRecord
  include ForInvestor
  include Trackable.new
  include FundUnitShared

  include RansackerAmounts.new(fields: %w[amount price premium])

  belongs_to :entity
  belongs_to :fund
  attr_readonly :fund_id # never moves to another fund (funds_api_security_policy_plan.md, B)
  belongs_to :capital_commitment
  belongs_to :investor
  belongs_to :owner, polymorphic: true, optional: true

  validates :unit_type, length: { maximum: 40 }
  validates :owner_type, length: { maximum: 255 }
  validates :quantity, presence: true

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

  # Stats cards above the Fund Units list, over `scope` (one LP's or one folio's units). Each card is the
  # total of a grid column as displayed: units held per unit type (Quantity - never added across unit
  # types, which are different instruments) and Amount. Amount cells show whole paise/cents cut from
  # fractional cents, so each row is truncated the same way before adding.
  def self.grid_totals(scope)
    rows = scope.pluck(:unit_type, :quantity, :amount_cents)
    units_by_type = rows.group_by(&:first).transform_values { |r| r.sum { |_, quantity, _| quantity } }
    { units_by_type: units_by_type.sort_by { |type, _| type.to_s }.to_h, amount: rows.sum { |_, _, amount| amount.truncate } }
  end

  def to_s
    unit_type
  end

  before_save :calculate_amount_cents
  def calculate_amount_cents
    self.amount_cents = quantity * (price_cents + premium_cents)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[issue_date premium price amount quantity reason unit_type capital_commitment_id fund_id owner_type].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[capital_commitment investor]
  end
end
