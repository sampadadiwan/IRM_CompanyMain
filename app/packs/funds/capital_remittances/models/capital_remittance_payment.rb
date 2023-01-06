class CapitalRemittancePayment < ApplicationRecord
  belongs_to :fund
  belongs_to :capital_remittance
  belongs_to :entity

  belongs_to :form_type, optional: true
  serialize :properties, Hash

  include FileUploader::Attachment(:payment_proof)

  monetize :amount_cents, with_currency: ->(i) { i.fund.currency }

  counter_culture :capital_remittance,
                  column_name: 'collected_amount_cents',
                  delta_column: 'amount_cents'

  validates_uniqueness_of :reference_no, scope: :fund_id, if: -> { reference_no.present? }
end
