class InvestmentSnapshot < ApplicationRecord
  belongs_to :investor
  belongs_to :entity
  belongs_to :funding_round
  belongs_to :investment

  monetize :amount_cents, :price_cents, with_model_currency: :currency
end
