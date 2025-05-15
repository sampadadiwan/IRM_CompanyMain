class CapitalRemittance < ApplicationRecord
  include Trackable.new
  include ForInvestor
  include WithFolder
  include WithCustomField
  include WithExchangeRate
  include CapitalRemittanceFees
  include CapitalRemittanceCallBasis
  include RansackerAmounts.new(fields: %w[call_amount collected_amount capital_fee other_fee arrear_amount])

  STANDARD_COLUMNS = {
    "Stakeholder" => "investor_name",
    "Folio No" => "folio_id",
    "Status" => "status",
    "Verified" => "verified",
    "Due Amount" => "due_amount",
    "Collected Amount" => "collected_amount",
    "Payment Date" => "payment_date"
  }.freeze

  INVESTOR_STANDARD_COLUMNS = {
    "Capital Call" => "capital_call_name",
    "Folio Id" => "folio_id",
    "Status" => "status",
    "Due Amount" => "due_amount",
    "Collected Amount" => "collected_amount",
    "Payment Date" => "payment_date"
  }.freeze

  FOR_COMMITMENT_COLUMNS = {
    "Capital Call" => "capital_call_name",
    "Status" => "status",
    "Verified" => "verified",
    "Due Amount" => "due_amount",
    "Collected Amount" => "collected_amount",
    "Payment Date" => "payment_date"
  }.freeze

  update_index('capital_remittance') { self if index_record? }

  belongs_to :entity
  belongs_to :fund, touch: true
  belongs_to :capital_call
  belongs_to :capital_commitment
  has_one :investor_kyc, through: :capital_commitment
  belongs_to :investor
  belongs_to :exchange_rate, optional: true
  has_many :capital_remittance_payments, dependent: :destroy
  has_many :fund_units, as: :owner, dependent: :destroy
  has_many :noticed_events, as: :record, dependent: :destroy, class_name: "Noticed::Event"

  has_many :commitment_adjustments, as: :owner, dependent: :destroy

  scope :paid, -> { where(status: "Paid") }
  scope :pending, -> { where(status: "Pending") }
  scope :verified, -> { where(verified: true) }

  monetize :tracking_collected_amount_cents, :tracking_call_amount_cents,
           with_currency: ->(i) { i.fund.tracking_currency.presence || i.fund.currency }

  monetize :call_amount_cents, :capital_fee_cents, :other_fee_cents, :collected_amount_cents, :computed_amount_cents, :committed_amount_cents, :arrear_amount_cents, with_currency: ->(i) { i.fund.currency }
  monetize :folio_call_amount_cents, :folio_capital_fee_cents, :folio_other_fee_cents, :folio_collected_amount_cents, :folio_committed_amount_cents, :arrear_folio_amount_cents, with_currency: ->(i) { i.capital_commitment.folio_currency }

  validates :folio_id, presence: true
  validates_uniqueness_of :folio_id, scope: :capital_call_id
  validates :folio_committed_amount_cents, numericality: { greater_than: 0 }

  validates :status, length: { maximum: 10 }
  validates :folio_id, length: { maximum: 20 }
  validates :investor_name, length: { maximum: 255 }

  include CapitalRemittanceCounters

  def set_call_amount
    self.remittance_date ||= capital_call.call_date
    # This is the committed_amount when the remittance was created. In certain special top up cases the committed_amount for the commitment may be changed later. Hence this is a ref for the committed_amount at the time of creation
    self.folio_committed_amount_cents = capital_commitment.folio_committed_amount_cents
    self.committed_amount_cents = capital_commitment.committed_amount_cents

    calc_call_amount_cents
    # Setup Paid or Pending status
    set_status
  end

  def calc_call_amount_cents
    # Convert between folio and fund currencies
    convert_fees

    # Case where we allocate based on percentage of commitment
    if capital_call.call_basis == "Percentage of Commitment" && call_amount_cents.zero?
      call_basis_percentage_commitment

    # Case where the capital remittances will be uploaded manually
    elsif capital_call.call_basis == "Upload"
      call_basis_upload

    # Special case where the call_basis is Investable Capital Percentage or Foreign Investable Capital Percentage
    elsif call_amount_cents.zero?
      call_basis_account_entry(capital_call.call_basis)

    end
  end

  def exchange_rate_adjustments
    # Adjust for exchange rates on the day of the payment
  end

  def send_notification(reminder: false)
    if capital_call.send_call_notice_flag && capital_call.approved && !capital_call.manual_generation
      investor.notification_users(fund).each do |user|
        email_method = reminder ? :reminder_capital_remittance : :notify_capital_remittance
        CapitalRemittanceNotifier.with(record: self, entity_id:, email_method:).deliver_later(user)
      end
    end
  end

  def payment_received_notification
    investor.notification_users(fund).each do |user|
      CapitalRemittanceNotifier.with(record: self, entity_id:, email_method: :payment_received).deliver_later(user)
    end
  end

  before_save :set_investor_name
  def set_investor_name
    self.investor_name = investor.investor_name
  end

  def set_payment_date
    # The payment date is either the last capital_remittance_payments date
    last_payment = capital_remittance_payments.order("capital_remittance_payments.payment_date asc").last
    if last_payment
      # We have a payment, lets use its payment_date
      self.payment_date = last_payment.payment_date
    else
      # We have no payments, but we may have deleted all payments.
      payments_deleted = capital_remittance_payments.with_deleted.order("capital_remittance_payments.payment_date asc")
      self.payment_date = nil if payments_deleted.exists?
    end
    # Or the payment_date is when the capital_remittance is verified and there are no payments uploaded
    self.payment_date ||= capital_call.due_date if verified
  end

  def folder_path
    "#{capital_call.folder_path}/#{investor.investor_name.delete('/')}-#{folio_id.delete('/')}"
  end

  # Sets the status of the capital remittance based on the remittance generation basis and due amounts.
  #
  # The status is determined by the following logic:
  # - If the fund's remittance generation basis is "Folio Amount", the considered due amount is set to the folio due amount.
  # - If the fund's remittance generation basis is "Fund Amount", the considered due amount is set to the due amount.
  # - If the remittance generation basis is unknown, an error is raised.
  #
  # The status is then set based on the considered due amount:
  # - If the absolute value of the considered due amount is less than or equal to 10, the status is set to "Paid".
  # - If the considered due amount is less than or equal to -10, the status is set to "Overpaid".
  # - If the capital call's due date is in the future, the status is set to "Pending".
  # - Otherwise, the status is set to "Overdue".
  #
  # @raise [RuntimeError] if the fund's remittance generation basis is unknown.
  def set_status
    # Change the status only if the remittance is verified
    if verified
      considered_due_amount = folio_due_amount

      # Set the status based on the considered due amount and the capital call's due date
      self.status = if considered_due_amount.to_f.abs <= 10
                      "Paid"
                    elsif considered_due_amount.to_f <= -10
                      "Overpaid"
                    else
                      capital_call.due_date > Time.zone.today ? "Pending" : "Overdue"
                    end
    end
  end

  def net_call_amount
    call_amount + other_fee
  end

  def due_amount
    call_amount + other_fee - collected_amount
  end

  def folio_due_amount
    folio_call_amount + folio_other_fee - folio_collected_amount
  end

  def to_s
    "#{investor_name}: #{folio_id}"
    # if status == "Paid"
    #   "#{investor_name}: #{collected_amount} : #{status}"
    # else
    #   "#{investor_name}: #{due_amount} : #{status}"
    # end
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[call_amount collected_amount capital_fee other_fee folio_id investor_name payment_date remittance_date status verified arrear_amount].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[capital_call capital_commitment fund investor]
  end

  after_destroy :touch_investor
  # rubocop:disable Rails/SkipsModelValidations
  # This is to bust any cached dashboards showing the commitments
  def touch_investor
    investor.investor_entity.touch if investor&.investor_entity
    entity.touch
  end
  # rubocop:enable Rails/SkipsModelValidations

  def has_arrears?
    arrear_amount_cents != 0
  end

  def tracking_exchange_rate_date
    remittance_date
  end

  def allocated_unit_amount_cents
    @allocated_unit_amt ||= fund_units.present? ? fund_units.sum(&:amount).cents : 0
    @allocated_unit_amt
  end

  def allocated_unit_amount_cents_before(fund_unit)
    # Get the fund units that are after the current fund unit
    units_before = fund_units.where(id: ..fund_unit.id)
    @allocated_unit_amt ||= units_before.present? ? units_before.sum(&:amount).cents : 0
    @allocated_unit_amt
  end

  def pending_amount_for_units_allocation
    if collected_amount_cents >= call_amount_cents
      amount_cents = call_amount_cents - allocated_unit_amount_cents
      reason = "Issuing units for net call amount #{money_to_currency(Money.new(amount_cents, fund.currency))}"
    else
      amount_cents = collected_amount_cents - allocated_unit_amount_cents
      reason = "Issuing units for net collected amount #{money_to_currency(Money.new(amount_cents, fund.currency))}"
    end

    [amount_cents, reason]
  end
end
