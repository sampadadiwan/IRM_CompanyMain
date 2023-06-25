class InvestmentSnapshot < ApplicationRecord
  belongs_to :investor
  belongs_to :entity
  belongs_to :funding_round
  belongs_to :investment

  monetize :amount_cents, :price_cents, with_model_currency: :currency

  validates :investment_type, :investor_type, :investment_instrument, :category, length: { maximum: 100 }
  validates :status, :tag, length: { maximum: 20 }
  validates :currency, length: { maximum: 10 }
  validates :units, length: { maximum: 15 }
  validates :spv, :anti_dilution, length: { maximum: 50 }
  validates :liq_pref_type, length: { maximum: 25 }
end
