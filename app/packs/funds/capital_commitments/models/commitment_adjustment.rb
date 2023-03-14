class CommitmentAdjustment < ApplicationRecord
  include WithExchangeRate
  belongs_to :entity
  belongs_to :fund
  belongs_to :capital_commitment

  validates :reason, :as_of, :folio_amount_cents, presence: true

  monetize :folio_amount_cents, with_currency: ->(i) { i.capital_commitment.folio_currency }
  monetize :amount_cents, :pre_adjustment_cents, :post_adjustment_cents, with_currency: ->(i) { i.fund.currency }

  counter_culture :capital_commitment, column_name: 'adjustment_amount_cents', delta_column: 'amount_cents'
  counter_culture :capital_commitment, column_name: 'adjustment_folio_amount_cents', delta_column: 'folio_amount_cents'

  before_save :update_amounts
  def update_amounts
    # Convert
    self.amount_cents = convert_currency(capital_commitment.folio_currency, fund.currency, folio_amount_cents) if folio_amount_cents != 0
    # Update Pre/Post
    self.pre_adjustment_cents = capital_commitment.committed_amount_cents
    self.post_adjustment_cents = amount_cents + pre_adjustment_cents
  end

  after_save -> { capital_commitment.reload.save }
  after_destroy -> { capital_commitment.reload.save }
end
