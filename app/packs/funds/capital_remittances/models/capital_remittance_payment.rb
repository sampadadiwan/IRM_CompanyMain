class CapitalRemittancePayment < ApplicationRecord
  include WithCustomField
  include WithExchangeRate
  include ForInvestor
  include Trackable.new

  belongs_to :fund
  belongs_to :capital_remittance
  belongs_to :entity

  include FileUploader::Attachment(:payment_proof)

  monetize :amount_cents, with_currency: ->(i) { i.fund.currency }
  monetize :folio_amount_cents, with_currency: ->(i) { i.capital_remittance.capital_commitment.folio_currency }

  before_save :set_amount, if: :folio_amount_cents_changed?

  counter_culture :capital_remittance,
                  column_name: 'collected_amount_cents',
                  delta_column: 'amount_cents',
                  execute_after_commit: true

  counter_culture :capital_remittance,
                  column_name: 'folio_collected_amount_cents',
                  delta_column: 'folio_amount_cents',
                  execute_after_commit: true

  # This must come after the counter_cultures above
  after_commit :unverify_remittance, unless: :destroyed?

  validates_uniqueness_of :reference_no, scope: :fund_id, if: -> { reference_no.present? }
  validates :reference_no, length: { maximum: 40 }

  def set_amount
    # Since the remittance amount is always in the folio currency, we compute the converted amount based on exchange rates.
    self.amount_cents = convert_currency(capital_remittance.capital_commitment.folio_currency, fund.currency,
                                         folio_amount_cents, payment_date)
  end

  def unverify_remittance
    capital_remittance.reload
    capital_remittance.verified = false
    CapitalRemittanceUpdate.call(capital_remittance:)
  end

  def to_s
    "#{capital_remittance.investor_name} - #{amount}"
  end
end
