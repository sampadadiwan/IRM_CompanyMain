class CapitalRemittance < ApplicationRecord
  include ActivityTrackable
  tracked owner: proc { |_controller, model| model.fund }, entity_id: proc { |_controller, model| model.entity_id }
  include Trackable
  include ForInvestor
  include WithFolder
  include WithCustomField
  include WithExchangeRate

  update_index('capital_remittance') { self }

  belongs_to :entity
  belongs_to :fund, touch: true
  belongs_to :capital_call
  belongs_to :capital_commitment
  has_one :investor_kyc, through: :capital_commitment
  belongs_to :investor
  belongs_to :exchange_rate, optional: true
  has_many :capital_remittance_payments, dependent: :destroy
  has_many :notifications, as: :recipient, dependent: :destroy

  scope :paid, -> { where(status: "Paid") }
  scope :pending, -> { where(status: "Pending") }
  scope :verified, -> { where(verified: true) }
  scope :pool, -> { joins(:capital_commitment).where("capital_commitments.commitment_type=?", "Pool") }
  scope :co_invest, -> { joins(:capital_commitment).where("capital_commitments.commitment_type=?", "CoInvest") }

  monetize :call_amount_cents, :capital_fee_cents, :other_fee_cents, :collected_amount_cents, :computed_amount_cents, :committed_amount_cents, with_currency: ->(i) { i.fund.currency }
  monetize :folio_call_amount_cents, :folio_capital_fee_cents, :folio_other_fee_cents, :folio_collected_amount_cents, :folio_committed_amount_cents, with_currency: ->(i) { i.capital_commitment.folio_currency }

  validates :folio_id, presence: true
  validates_uniqueness_of :folio_id, scope: :capital_call_id
  validates :folio_committed_amount_cents, :folio_call_amount_cents, numericality: { greater_than: 0 }

  validates :status, length: { maximum: 10 }
  validates :folio_id, length: { maximum: 20 }
  validates :investor_name, length: { maximum: 255 }

  before_save :set_call_amount

  counter_culture :capital_call, column_name: 'capital_fee_cents',
                                 delta_column: 'capital_fee_cents',
                                 execute_after_commit: true

  counter_culture :capital_call, column_name: 'other_fee_cents',
                                 delta_column: 'other_fee_cents',
                                 execute_after_commit: true

  counter_culture :fund, column_name: 'capital_fee_cents',
                         delta_column: 'capital_fee_cents',
                         execute_after_commit: true

  counter_culture :fund, column_name: 'other_fee_cents',
                         delta_column: 'other_fee_cents',
                         execute_after_commit: true

  counter_culture :capital_call, column_name: proc { |r| r.verified ? 'collected_amount_cents' : nil },
                                 delta_column: 'collected_amount_cents',
                                 column_names: {
                                   ["capital_remittances.verified = ?", true] => 'collected_amount_cents'
                                 },
                                 execute_after_commit: true

  counter_culture :capital_commitment, column_name: proc { |r| r.verified ? 'folio_collected_amount_cents' : nil },
                                       delta_column: 'folio_collected_amount_cents',
                                       column_names: {
                                         ["capital_remittances.verified = ?", true] => 'folio_collected_amount_cents'
                                       },
                                       execute_after_commit: true

  counter_culture :capital_commitment, column_name: 'call_amount_cents',
                                       delta_column: 'call_amount_cents',
                                       execute_after_commit: true

  counter_culture %i[capital_commitment investor_kyc], column_name: 'call_amount_cents',
                                                       delta_column: 'call_amount_cents',
                                                       execute_after_commit: true

  counter_culture :fund, column_name: proc { |r| r.capital_commitment.Pool? ? 'call_amount_cents' : 'co_invest_call_amount_cents' },
                         delta_column: 'call_amount_cents',
                         column_names: lambda {
                                         {
                                           CapitalRemittance.pool => :call_amount_cents,
                                           CapitalRemittance.co_invest => :co_invest_call_amount_cents
                                         }
                                       },
                         execute_after_commit: true

  counter_culture :capital_call, column_name: 'call_amount_cents',
                                 delta_column: 'call_amount_cents',
                                 execute_after_commit: true

  counter_culture :capital_commitment, column_name: 'folio_call_amount_cents',
                                       delta_column: 'folio_call_amount_cents',
                                       execute_after_commit: true

  counter_culture :capital_commitment, column_name: proc { |r| r.verified ? 'collected_amount_cents' : nil },
                                       delta_column: 'collected_amount_cents',
                                       column_names: {
                                         ["capital_remittances.verified = ?", true] => 'collected_amount_cents'
                                       },
                                       execute_after_commit: true

  counter_culture %i[capital_commitment investor_kyc], column_name: proc { |r| r.verified ? 'collected_amount_cents' : nil },
                                                       delta_column: 'collected_amount_cents',
                                                       column_names: {
                                                         ["capital_remittances.verified = ?", true] => 'collected_amount_cents'
                                                       },
                                                       execute_after_commit: true

  counter_culture :fund, column_name:
                        proc { |r| r.verified && r.capital_commitment.Pool? ? 'collected_amount_cents' : nil },
                         delta_column: 'collected_amount_cents',
                         column_names: lambda {
                                         {
                                           CapitalRemittance.verified.pool => :collected_amount_cents
                                         }
                                       },
                         execute_after_commit: true

  counter_culture :fund, column_name:
                        proc { |r| r.verified && r.capital_commitment.CoInvest? ? 'co_invest_collected_amount_cents' : nil },
                         delta_column: 'collected_amount_cents',
                         column_names: lambda {
                                         {
                                           CapitalRemittance.verified.co_invest => :co_invest_collected_amount_cents
                                         }
                                       },
                         execute_after_commit: true

  def set_call_amount
    # This is the committed_amount when the remittance was created. In certain special top up cases the committed_amount for the commitment may be changed later. Hence this is a ref for the committed_amount at the time of creation
    self.folio_committed_amount_cents = capital_commitment.folio_committed_amount_cents
    self.committed_amount_cents = capital_commitment.committed_amount_cents

    calc_call_amount_cents
    # Setup Paid or Pending status
    set_status
  end

  def calc_call_amount_cents
    if capital_call.call_basis == "Upload"
      # Also for some calls, fees will be included so we convert to folio_currency
      self.capital_fee_cents = folio_capital_fee_cents.positive? ? convert_currency(capital_commitment.folio_currency, fund.currency, folio_capital_fee_cents, payment_date) : 0

      self.other_fee_cents = folio_other_fee_cents.positive? ? convert_currency(capital_commitment.folio_currency, fund.currency, folio_other_fee_cents, payment_date) : 0
    else
      # Also for some calls, fees will be included so we convert to folio_currency
      self.folio_capital_fee_cents = capital_fee_cents.positive? ? convert_currency(fund.currency, capital_commitment.folio_currency, capital_fee_cents, payment_date) : 0

      self.folio_other_fee_cents = other_fee_cents.positive? ? convert_currency(fund.currency, capital_commitment.folio_currency, other_fee_cents, payment_date) : 0
    end

    # Get the call amount in the folio_currency
    if capital_call.call_basis == "Percentage of Commitment" && call_amount_cents.zero?

      self.percentage = capital_call.percentage_called
      self.folio_call_amount_cents = percentage * capital_commitment.folio_committed_amount_cents / 100.0

      # Now compute the call amount in the fund currency.
      self.computed_amount_cents = convert_currency(capital_commitment.folio_currency, fund.currency, folio_call_amount_cents, payment_date)

      # Now add the capital fees
      self.folio_call_amount_cents += folio_capital_fee_cents
      self.call_amount_cents = computed_amount_cents + capital_fee_cents

    elsif capital_call.call_basis == "Amount allocated on Investable Capital" && call_amount_cents.zero?
      # Get the IC percentage
      self.percentage = capital_commitment.account_entries.where(name: "Investable Capital Percentage", reporting_date: ..capital_call.due_date).order(reporting_date: :desc).first&.amount_cents || 0

      self.computed_amount_cents = capital_call.amount_to_be_called_cents * percentage / 100.0

      self.call_amount_cents = computed_amount_cents + capital_fee_cents

      # Now compute the folio call amount in the folio currency.
      self.folio_call_amount_cents = convert_currency(fund.currency, capital_commitment.folio_currency, call_amount_cents, payment_date)

    elsif capital_call.call_basis == "Upload"
      # This is for direct upload of remittances, where the folio_call_amount includes the capital fees
      self.folio_call_amount_cents -= folio_capital_fee_cents

      # Now compute the call amount in the fund currency.
      self.computed_amount_cents = convert_currency(capital_commitment.folio_currency, fund.currency, folio_call_amount_cents, payment_date)

      # Now add the capital fees
      self.folio_call_amount_cents += folio_capital_fee_cents
      self.call_amount_cents = computed_amount_cents + capital_fee_cents
    end
  end

  def exchange_rate_adjustments
    # Adjust for exchange rates on the day of the payment
  end

  def send_notification
    if capital_call.approved && !capital_call.manual_generation
      investor.approved_users.each do |user|
        CapitalRemittanceNotification.with(entity_id:, capital_remittance_id: id, email_method: :send_notification).deliver_later(user)
      end
    end
  end

  def payment_received_notification
    investor.approved_users.each do |user|
      CapitalRemittanceNotification.with(entity_id:, capital_remittance_id: id, email_method: :payment_received).deliver_later(user)
    end
  end

  before_save :set_investor_name
  def set_investor_name
    self.investor_name = investor.investor_name
    # The payment date is either the last capital_remittance_payments date
    last_payment = capital_remittance_payments.order("capital_remittance_payments.payment_date asc").last
    self.payment_date = last_payment.payment_date if last_payment
    # Or the payment_date is when the capital_remittance is verified and there are no payments uploaded
    self.payment_date ||= capital_call.due_date if verified
  end

  def folder_path
    "#{capital_call.folder_path}/Remittances/#{investor.investor_name.delete('/')}-#{folio_id.delete('/')}"
  end

  def set_status
    self.status = if due_amount.to_f.abs < 100
                    "Paid"
                  else
                    "Pending"
                  end
  end

  def due_amount
    computed_amount + capital_fee + other_fee - collected_amount
  end

  def folio_due_amount
    folio_call_amount - folio_collected_amount
  end

  def to_s
    if status == "Paid"
      "#{investor_name}: #{collected_amount} : #{status}"
    else
      "#{investor_name}: #{due_amount} : #{status}"
    end
  end

  def setup_call_fees
    total_capital_fees_cents = 0
    total_other_fees_cents = 0

    if capital_call.call_fees.present?

      capital_call.call_fees.each do |call_fee|
        # Sum the amount for the fee for the commitment account_entries
        fees = capital_commitment.account_entries.where("account_entries.reporting_date >=? and account_entries.reporting_date <=? and account_entries.name = ? and cumulative = ?", call_fee.start_date, call_fee.end_date, call_fee.name, false).sum(:amount_cents)

        call_fee.fee_type == "Other Fees" ? total_other_fees_cents += fees : total_capital_fees_cents += fees
      end

    end

    Rails.logger.debug { "### #{investor_name} total_capital_fees_cents: #{total_capital_fees_cents}, total_other_fees_cents: #{total_other_fees_cents}" }

    self.capital_fee_cents = total_capital_fees_cents
    self.other_fee_cents = total_other_fees_cents
  end
end
