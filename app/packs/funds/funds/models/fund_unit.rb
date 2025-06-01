class FundUnit < ApplicationRecord
  include ForInvestor

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
  counter_culture :fund, column_name: 'total_units_premium_cents', delta_column: 'total_premium_cents'

  def to_s
    unit_type
  end

  def amount_cents
    quantity * (price_cents + premium_cents)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[issue_date premium price quantity reason unit_type].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[capital_commitment investor]
  end
end
