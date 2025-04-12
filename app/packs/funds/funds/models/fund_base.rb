class FundBase < ApplicationRecord
  self.abstract_class = true
  acts_as_favoritable
  include ForInvestor
  include WithCustomField

  CATEGORIES = ["Category I", "Category II", "Category III"].freeze
  REMITTANCE_GENERATION_BASIS = ["Folio Amount", "Fund Amount"].freeze

  monetize  :tracking_committed_amount_cents, :tracking_call_amount_cents,
            :tracking_collected_amount_cents, :tracking_distribution_amount_cents,
            with_currency: ->(f) { f.tracking_currency.presence || f.currency }

  monetize :call_amount_cents, :committed_amount_cents, :target_committed_amount_cents,
           :collected_amount_cents, :distribution_amount_cents, :total_units_premium_cents,
           with_currency: ->(f) { f.currency }
end
