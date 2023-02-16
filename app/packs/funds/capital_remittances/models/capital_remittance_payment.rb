class CapitalRemittancePayment < ApplicationRecord
  include WithCustomField
  include FundScopes

  belongs_to :fund
  belongs_to :capital_remittance
  belongs_to :entity

  include FileUploader::Attachment(:payment_proof)

  monetize :amount_cents, with_currency: ->(i) { i.fund.currency }

  counter_culture :capital_remittance,
                  column_name: 'collected_amount_cents',
                  delta_column: 'amount_cents'

  validates_uniqueness_of :reference_no, scope: :fund_id, if: -> { reference_no.present? }

  delegate :to_s, to: :amount
end
