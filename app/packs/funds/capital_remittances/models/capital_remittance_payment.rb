class CapitalRemittancePayment < ApplicationRecord
  include WithCustomField
  include WithExchangeRate
  include ForInvestor
  include Trackable.new
  include RansackerAmounts.new(fields: %w[amount folio_amount tracking_amount])

  belongs_to :fund
  belongs_to :capital_remittance
  delegate :capital_call, to: :capital_remittance
  has_one :investor, through: :capital_remittance
  delegate :capital_commitment, to: :capital_remittance
  belongs_to :entity
  has_many :noticed_events, as: :record, dependent: :destroy, class_name: "Noticed::Event"

  include FileUploader::Attachment(:payment_proof)

  monetize :amount_cents, with_currency: ->(i) { i.fund.currency }
  monetize :folio_amount_cents, with_currency: ->(i) { i.capital_remittance.capital_commitment.folio_currency }
  monetize :tracking_amount_cents, with_currency: ->(i) { i.fund.tracking_currency.presence || i.fund.currency }

  counter_culture :capital_remittance,
                  column_name: 'tracking_collected_amount_cents',
                  delta_column: 'tracking_amount_cents',
                  execute_after_commit: true

  counter_culture :capital_remittance,
                  column_name: 'collected_amount_cents',
                  delta_column: 'amount_cents',
                  execute_after_commit: true

  counter_culture :capital_remittance,
                  column_name: 'folio_collected_amount_cents',
                  delta_column: 'folio_amount_cents',
                  execute_after_commit: true

  # This must come after the counter_cultures above
  after_commit :unverify_remittance # , unless: ->(crp) { crp.deleted? || crp.destroyed? }

  validates_uniqueness_of :reference_no, scope: :fund_id, if: -> { reference_no.present? }
  validates :reference_no, length: { maximum: 40 }

  def set_amount
    # Since the remittance amount is always in the folio currency, we compute the converted amount based on exchange rates. In imports we have the amount_cents also already setup, so no conversion is needed
    self.amount_cents = convert_currency(capital_remittance.capital_commitment.folio_currency, fund.currency, folio_amount_cents, payment_date)
  end

  # Called after create, and also after remittance is verified (CapitalRemittanceVerify)
  def notify_capital_remittance_payment
    # Check before sending notification
    # 1. if the capital call has the send_payment_notification_flag set to true and
    # 2. if the capital remittance is verified
    # 3. if the payment notification has not been sent
    if  capital_call.send_payment_notification_flag &&
        capital_remittance.verified && amount_cents.positive? &&
        !payment_notification_sent
      # Send email notification to all approved users of the investor
      investor.notification_users(fund).each do |user|
        email_method = :notify_capital_remittance_payment
        CapitalRemittancePaymentNotifier.with(record: self, entity_id:, email_method:).deliver_later(user)
      end

      # Mark this as sent, so we dont resend duplicate notifications
      # rubocop:disable Rails/SkipsModelValidations
      update_column(:payment_notification_sent, true)
      # rubocop:enable Rails/SkipsModelValidations
    end
  end

  def unverify_remittance
    # When the payment is deleted, we need to unverify the remittance, but sometimes the call itself is deleted, which delete the remittance, so we need to check for whether the remittance is deleted or not
    unless capital_remittance.deleted? || capital_remittance.destroyed?
      capital_remittance.reload
      capital_remittance.verified = false
      CapitalRemittanceUpdate.call(capital_remittance:)
    end
  end

  def to_s
    "#{capital_remittance.investor_name} - #{amount}"
  end

  # This is the date used to find the exchange rate for the tracking currency
  def tracking_exchange_rate_date
    payment_date
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[created_at updated_at payment_date capital_remittance_id payment_notification_sent reference_no amount folio_amount tracking_amount].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[fund capital_remittance investor]
  end
end
