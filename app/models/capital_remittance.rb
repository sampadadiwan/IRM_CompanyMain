class CapitalRemittance < ApplicationRecord
  belongs_to :entity
  belongs_to :fund
  belongs_to :capital_call
  belongs_to :investor

  monetize :due_amount_cents, :collected_amount_cents, with_currency: ->(i) { i.entity.currency }

  def due
    commitment = fund.capital_commitments.where(investor_id:).first
    commitment ? capital_call.percentage_called * commitment.committed_amount / 100 : 0
  end
end
