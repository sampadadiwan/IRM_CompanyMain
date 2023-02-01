class FundUnit < ApplicationRecord
  include FundScopes

  belongs_to :entity
  belongs_to :fund
  belongs_to :capital_commitment
  belongs_to :investor
  belongs_to :owner, polymorphic: true, optional: true

  counter_culture :capital_commitment, column_name: 'total_fund_units_quantity', delta_column: 'quantity'
end
