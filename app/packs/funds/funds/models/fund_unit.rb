class FundUnit < ApplicationRecord
  include FundScopes

  belongs_to :entity
  belongs_to :fund
  belongs_to :capital_commitment
  belongs_to :investor
  belongs_to :owner, polymorphic: true, optional: true

  monetize :total_premium_cents, with_currency: ->(i) { i.fund.currency }

  counter_culture :owner, column_name: 'units_quantity', delta_column: 'quantity'

  counter_culture :capital_commitment, column_name: 'total_fund_units_quantity', delta_column: 'quantity'
  counter_culture :capital_commitment, column_name: 'total_units_premium_cents', delta_column: 'total_premium_cents'
  counter_culture :fund, column_name: 'total_units_premium_cents', delta_column: 'total_premium_cents'

  def to_s
    unit_type
  end
end
