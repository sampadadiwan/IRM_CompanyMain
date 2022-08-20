class CapitalRemittance < ApplicationRecord
  belongs_to :entity
  belongs_to :fund
  belongs_to :capital_call
  belongs_to :capital_commitment
  belongs_to :investor

  monetize :due_amount_cents, :collected_amount_cents, with_currency: ->(i) { i.entity.currency }

  before_validation :set_capital_commitment
  def set_capital_commitment
    self.capital_commitment = fund.capital_commitments.where(investor_id:).first
  end

  counter_culture :capital_call, column_name: proc { |o| o.status == 'Paid' ? 'collected_amount_cents' : nil },
                                 delta_column: 'collected_amount_cents'

  counter_culture :capital_call, column_name: proc { |o| o.status == 'Pending' ? 'due_amount_cents' : nil },
                                 delta_column: 'due_amount_cents'

  counter_culture :capital_commitment, column_name: proc { |o| o.status == 'Paid' ? 'collected_amount_cents' : nil },
                                       delta_column: 'collected_amount_cents'

  counter_culture :fund, column_name: proc { |o| o.status == 'Paid' ? 'collected_amount_cents' : nil },
                         delta_column: 'collected_amount_cents'

  def due
    capital_commitment ? capital_call.percentage_called * capital_commitment.committed_amount / 100 : 0
  end
end
