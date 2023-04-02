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

  scope :paid, -> { where(status: "Paid") }
  scope :pending, -> { where(status: "Pending") }
  scope :verified, -> { where(verified: true) }
  scope :pool, -> { joins(:capital_commitment).where("capital_commitments.commitment_type=?", "Pool") }
  scope :co_invest, -> { joins(:capital_commitment).where("capital_commitments.commitment_type=?", "CoInvest") }

  monetize :call_amount_cents, :collected_amount_cents, :committed_amount_cents, with_currency: ->(i) { i.fund.currency }
  monetize :folio_call_amount_cents, :folio_collected_amount_cents, :folio_committed_amount_cents, with_currency: ->(i) { i.capital_commitment.folio_currency }

  validates :folio_id, presence: true
  validates_uniqueness_of :folio_id, scope: :capital_call_id
  validates :folio_committed_amount_cents, :folio_call_amount_cents, numericality: { greater_than: 0 }

  counter_culture :capital_call, column_name: proc { |r| r.verified ? 'collected_amount_cents' : nil },
                                 delta_column: 'collected_amount_cents',
                                 column_names: {
                                   ["capital_remittances.verified = ?", true] => 'collected_amount_cents'
                                 }

  counter_culture :capital_commitment, column_name: proc { |r| r.verified ? 'folio_collected_amount_cents' : nil },
                                       delta_column: 'folio_collected_amount_cents',
                                       column_names: {
                                         ["capital_remittances.verified = ?", true] => 'folio_collected_amount_cents'
                                       }

  counter_culture :capital_commitment, column_name: 'call_amount_cents',
                                       delta_column: 'call_amount_cents'

  counter_culture :capital_commitment, column_name: 'folio_call_amount_cents',
                                       delta_column: 'folio_call_amount_cents'

  counter_culture :capital_commitment, column_name: proc { |r| r.verified ? 'collected_amount_cents' : nil },
                                       delta_column: 'collected_amount_cents',
                                       column_names: {
                                         ["capital_remittances.verified = ?", true] => 'collected_amount_cents'
                                       }

  counter_culture :fund, column_name:
                        proc { |r| r.verified && r.capital_commitment.Pool? ? 'collected_amount_cents' : nil },
                         delta_column: 'collected_amount_cents',
                         column_names: lambda {
                                         {
                                           CapitalRemittance.verified.pool => :collected_amount_cents
                                         }
                                       }

  counter_culture :fund, column_name:
                        proc { |r| r.verified && r.capital_commitment.CoInvest? ? 'co_invest_collected_amount_cents' : nil },
                         delta_column: 'collected_amount_cents',
                         column_names: lambda {
                                         {
                                           CapitalRemittance.verified.co_invest => :co_invest_collected_amount_cents
                                         }
                                       }

  before_save :set_status
  before_create :set_call_amount
  def set_call_amount
    # This is the committed_amount when the remittance was created. In certain special top up cases the committed_amount for the commitment may be changed later. Hence this is a ref for the committed_amount at the time of creation
    self.folio_committed_amount_cents = capital_commitment.folio_committed_amount_cents
    self.committed_amount_cents = capital_commitment.committed_amount_cents
    calc_call_amount_cents
    set_status
  end

  def calc_call_amount_cents
    # Get the call amount in the folio_currency
    self.folio_call_amount_cents = capital_call.percentage_called * capital_commitment.folio_committed_amount_cents / 100.0
    # Now compute the call amount in the fund currency
    self.call_amount_cents = convert_currency(capital_commitment.folio_currency, fund.currency,
                                              folio_call_amount_cents, payment_date)
  end

  def send_notification
    CapitalRemittancesMailer.with(id:).send_notification.deliver_later if capital_call.approved && !capital_call.manual_generation
  end

  def payment_received_notification
    CapitalRemittancesMailer.with(id:).payment_received.deliver_later
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
    self.status = if (call_amount_cents - collected_amount_cents).abs < 100
                    "Paid"
                  else
                    "Pending"
                  end
  end

  def due_amount
    call_amount - collected_amount
  end

  def to_s
    if status == "Paid"
      "#{investor_name}: #{collected_amount} : #{status}"
    else
      "#{investor_name}: #{due_amount} : #{status}"
    end
  end
end
