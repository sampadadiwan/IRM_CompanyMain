class CapitalRemittance < ApplicationRecord
  # Value objects for fee breakdown data passed to Sablon document templates.
  FeeEntry = Data.define(:name, :date, :amount) # one raw fee line from the fee audit JSON — immutable, fully known at construction
  # Struct (not Data.define) because total_amount_across_folios is annotated in a second pass
  # by the doc generator after consolidation, so the object must be mutable.
  ConsolidatedFee = Struct.new(:name, :amount, :date, :total_amount_across_folios, keyword_init: true) do
    def initialize(name:, amount:, date:, total_amount_across_folios: nil) = super
  end
  include Trackable.new
  include ForInvestor
  # Evergreen dealing dates: allot / cancel units after commit (guarded; open-ended-funds B5)
  include EvergreenSettlementHooks
  include WithFolder
  include WithCustomField
  include WithExchangeRate
  include CapitalRemittanceFees
  include CapitalRemittanceCallBasis
  include CapitalRemittanceShared
  include BlocksDestroyWithFundUnits
  include RansackerAmounts.new(fields: %w[call_amount collected_amount capital_fee other_fee arrear_amount])

  STANDARD_COLUMNS = {
    "Investing Entity; text-col" => "investing_entity_name; text-col",
    "Folio No; text-col" => "folio_id; text-col",
    "Status; text-col" => "status; text-col",
    "Verified; text-col" => "verified; text-col",
    "Due Amount; num-col" => "due_amount; num-col",
    "Collected Amount; num-col" => "collected_amount; num-col",
    "Payment Date; date-col" => "payment_date; date-col"
  }.freeze

  ADDITIONAL_COLUMNS = {
    "Tracking Committed; num-col" => "tracking_committed_amount; num-col",
    "Tracking Called; num-col" => "tracking_call_amount; num-col"
  }.freeze

  # LPs see collections on the verified basis (as the commitment counters do): a payment counts as
  # collected once the fund has verified it, and until then shows under "Under Verification".
  INVESTOR_STANDARD_COLUMNS = {
    "Capital Call; text-col" => "capital_call_name; text-col",
    "Folio Id; text-col" => "folio_id; text-col",
    "Status; text-col" => "lp_status; text-col",
    "Due Amount; num-col" => "lp_due_amount; num-col",
    "Collected Amount; num-col" => "verified_collected_amount; num-col",
    "Under Verification; num-col" => "under_verification_amount; num-col",
    "Payment Date; date-col" => "payment_date; date-col"
  }.freeze

  # Column header help (RansackTableHeader). The lp_* / verified_* / under_verification_* columns are
  # the LP grid's (verified basis); status / verified / due_amount / collected_amount the fund team's.
  COLUMN_HELP = {
    "lp_status" => "Where this call stands. 'Payment under verification' means the fund has recorded your payment and is confirming it",
    "lp_due_amount" => "What is still owed on this call: call amount + fees - payments the fund has verified",
    "verified_collected_amount" => "Payments the fund has received and verified for this call",
    "under_verification_amount" => "Payments the fund has recorded but not yet verified - still counted as due until verified",
    "status" => "Paid once the full amount is recorded (it may still await verification); otherwise Pending or Overdue by the call's due date, or Overpaid",
    "verified" => "Whether the fund has confirmed the recorded payment against its bank records",
    "due_amount" => "Call amount + fees - every recorded payment, verified or not (LPs see due on the verified basis)",
    "collected_amount" => "Every payment recorded for this call, verified or not",
    "payment_date" => "When the payment was received"
  }.freeze

  FOR_COMMITMENT_COLUMNS = {
    "Capital Call; text-col" => "capital_call_name; text-col",
    "Status; text-col" => "status; text-col",
    "Verified; text-col" => "verified; text-col",
    "Due Amount; num-col" => "due_amount; num-col",
    "Collected Amount; num-col" => "collected_amount; num-col",
    "Payment Date; date-col" => "payment_date; date-col"
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

  monetize :tracking_collected_amount_cents, :tracking_call_amount_cents,
           with_currency: ->(i) { i.fund.tracking_currency.presence || i.fund.currency }

  monetize :call_amount_cents, :investment_amount_cents, :capital_fee_cents, :other_fee_cents, :collected_amount_cents, :computed_amount_cents, :committed_amount_cents, :arrear_amount_cents, with_currency: ->(i) { i.fund.currency }
  monetize :folio_call_amount_cents, :folio_investment_amount_cents, :folio_capital_fee_cents, :folio_other_fee_cents, :folio_collected_amount_cents, :folio_committed_amount_cents, :arrear_folio_amount_cents, with_currency: ->(i) { i.capital_commitment.folio_currency }

  validates :folio_id, presence: true
  validates_uniqueness_of :folio_id, scope: :capital_call_id
  validates :folio_committed_amount_cents, numericality: { greater_than: 0 }

  validates :status, length: { maximum: 10 }
  validates :folio_id, length: { maximum: 40 }
  validates :investor_name, length: { maximum: 255 }

  # persisted? (not new_record?) is deliberate: this must NOT block CapitalRemittance being
  # created already-verified by CapitalCommitmentRemittanceJob/CapitalCallJob when a call has
  # generate_remittances_verified set (a bulk/import path for backfilling already-settled
  # calls) — only the interactive Verify action, which always updates an existing record.
  validate :verified_requires_approval, if: -> { persisted? && verified? && verified_changed? }

  include CapitalRemittanceCounters

  def set_call_amount(recompute_call_amount: false)
    self.remittance_date ||= capital_call.call_date
    # This is the committed_amount when the remittance was created. In certain special top up cases the committed_amount for the commitment may be changed later. Hence this is a ref for the committed_amount at the time of creation
    self.folio_committed_amount_cents = capital_commitment.folio_committed_amount_cents
    self.committed_amount_cents = capital_commitment.committed_amount_cents

    calc_call_amount_cents(recompute_call_amount:)
    # Setup Paid or Pending status
    set_status
  end

  def calc_call_amount_cents(recompute_call_amount: false)
    # Convert between folio and fund currencies
    convert_fees
    # The call_basis should be set from the capital_call if not already set, only in case of uploads where we may have set it already
    self.call_basis ||= capital_call.call_basis

    # Case where we allocate based on percentage of commitment
    if call_basis == "Percentage of Commitment" && (call_amount_cents.zero? || recompute_call_amount)
      call_basis_percentage_commitment

    # Case where the capital remittances will be uploaded manually
    elsif call_basis == "Upload"
      call_basis_upload

    # Special case where the call_basis is Investable Capital Percentage or Foreign Investable Capital Percentage
    elsif call_amount_cents.zero? || recompute_call_amount
      call_basis_account_entry(call_basis) && (call_amount_cents.zero? || recompute_call_amount)
    end
  end

  def exchange_rate_adjustments
    # Adjust for exchange rates on the day of the payment
  end

  # Reasons "Send Call Notification" would not actually reach an investor right now.
  # Empty means it's safe to send. Used to grey out the action in the UI (with an
  # explanatory tooltip) and to guard the controller so a direct request can't silently
  # no-op the way send_notification's own internal checks would otherwise allow.
  def notification_blocked_reasons
    reasons = []
    reasons << "the call is not approved" unless capital_call.approved?
    reasons << "the call is set up to not send notifications" unless capital_call.send_call_notice_flag
    reasons << "the commitment has 'Skip Doc Gen' set to Yes" if capital_commitment.skip_doc_gen?
    # Mirrors CapitalRemittanceRuleContextProvider#notice_not_approved, promoted from a
    # client-side-only blocker rule to a real server-side gate.
    reasons << "the generated call notice for this remittance is pending approval" if Document.exists?(
      owner_type: "CapitalRemittance", owner_id: id, owner_tag: "Generated", approved: false
    )
    reasons << "no investor contacts are subscribed to Capital Call notifications" unless investor.capital_call_subscribers?(fund)
    # Attachment size, checked HERE and not only at send time. This button is the one call path
    # with no batch preflight - it sends a single remittance directly - so without this the
    # controller reports "Sent notification.", the mailer then refuses the oversized attachment,
    # and the operator finds out from a skipped-notification report minutes later. Both callers
    # of this method use it pre-emptively (the show page greys the button out and lists the
    # reasons; the controller refuses the request), so adding it here covers both.
    reasons.concat(NotificationAttachmentPreflight.violations(oversized_check_documents))
    reasons
  end

  # Mirrors CapitalRemittanceMailer#attach_all_files plus the notification's own uploads, which
  # is what an email for THIS remittance would carry. The notification is resolved the same way
  # #send_notification resolves it, so a reminder is judged on the reminder template.
  def oversized_check_documents
    email_method = notification_sent ? :reminder_capital_remittance : :notify_capital_remittance
    NotificationAttachmentPreflight.auto_attached_documents(self) +
      NotificationAttachmentPreflight.custom_notification_documents(capital_call.custom_notification(email_method), self)
  end
  private :oversized_check_documents

  # Reasons the payment-received notification would not actually reach the investor.
  # That notification has no manual send control of its own — it's fired automatically,
  # once per payment, by CapitalRemittanceVerify's payment_received_notification step
  # (see CapitalRemittancePayment#notify_capital_remittance_payment for the conditions
  # mirrored here). Surfaced in the Verify confirm message instead of a separate button.
  # `verified` itself is deliberately not checked — becoming verified is the point of the
  # action this message is shown for.
  def payment_notification_blocked_reasons
    reasons = []
    reasons << "the call is not approved" unless capital_call.approved?
    reasons << "the call is set up to not send payment notifications" unless capital_call.send_payment_notification_flag
    reasons << "there are no recorded payments with a positive amount" if capital_remittance_payments.where("amount_cents > 0").none?
    reasons << "a payment notification has already been sent for every recorded payment" if capital_remittance_payments.any? && capital_remittance_payments.where(payment_notification_sent: false).none?
    reasons << "no investor contacts are subscribed to Capital Call notifications" unless investor.capital_call_subscribers?(fund)
    reasons
  end

  def send_notification(reminder: false)
    if capital_call.send_call_notice_flag && capital_call.approved && !capital_commitment.skip_doc_gen? # skip sending notification if skip_doc_gen is set to yes
      investor.notification_users(fund, with_tag: 'CapitalCall').each do |user|
        email_method = reminder ? :reminder_capital_remittance : :notify_capital_remittance
        CapitalRemittanceNotifier.with(record: self, entity_id:, email_method:).deliver_later(user)
      end

      update_column(:notification_sent, true)
      # rubocop:enable Rails/SkipsModelValidations
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

    else
      # If the remittance is not verified, set the status to "Pending"
      self.status = "Pending"
    end
  end

  def net_call_amount
    call_amount + other_fee
  end

  def verified_requires_approval
    return if capital_call.approved?

    errors.add(:verified, "cannot be set while the call is not approved")
  end

  def due_amount
    call_amount + other_fee - collected_amount
  end

  # --- LP view: verified basis (investor grid columns + stats cards) ---
  # Collected only once the fund has verified the payment - the same basis as the commitment and
  # fund counters (CapitalRemittanceCounters), so the LP's Due matches their commitment card.
  def verified_collected_amount
    verified ? collected_amount : Money.new(0, collected_amount.currency)
  end

  # Recorded by the fund but not yet verified - shown to the LP so a paid call isn't silently "due"
  def under_verification_amount
    verified ? Money.new(0, collected_amount.currency) : collected_amount
  end

  # Status as the LP reads it: flag a recorded payment the fund hasn't verified yet, so a paid call
  # doesn't look like a plain "Overdue"/"Pending" default. The stored status is unchanged.
  def lp_status
    return status if verified || collected_amount_cents.to_d.zero?

    "#{status} · Payment under verification"
  end

  # What the LP still owes once only verified payments count (#due_amount counts every recorded payment)
  def lp_due_amount
    call_amount + other_fee - verified_collected_amount
  end

  # Stats cards above a remittance list (LP fund page Calls section, commitment page Remittances tab)
  # and the commitment card's Due Amount, over `scope`. Every card is the total of a column of the
  # grid the user sees, so they can never disagree:
  #   verified_basis: true  - the LP grid (INVESTOR_STANDARD_COLUMNS):
  #     Collected = "Collected Amount" (#verified_collected_amount),
  #     Under Verification = "Under Verification", Due = "Due Amount" (#lp_due_amount)
  #   verified_basis: false - the fund team's grid (STANDARD_COLUMNS / FOR_COMMITMENT_COLUMNS):
  #     Collected = "Collected Amount" (every recorded payment), Due = "Due Amount" (#due_amount),
  #     Unverified = Collected Amount of rows with Verified = No
  #   Called = Due + Collected; Overdue = Due Amount of the rows whose Status is Overdue, and how many
  # Amounts carry fractional paise and the grid shows each cell cut to whole paise (Money formatter
  # trims the decimals), so each cell is truncated the same way before adding - summing first could
  # show a paisa more. Plucks 5 columns of one LP's / one folio's rows, so it stays small.
  def self.grid_totals(scope, verified_basis:)
    rows = scope.pluck(:call_amount_cents, :other_fee_cents, :collected_amount_cents, :verified, :status)
    totals = { collected: 0, under_verification: 0, due: 0, overdue: 0, overdue_count: 0 }
    rows.each do |call, fee, got, verified, status|
      # Exactly what the row's cells display on this grid
      counted = verified_basis && !verified ? 0 : got
      row_due = (call + fee - counted).truncate
      totals[:collected] += counted.truncate
      # LP grid: its Under Verification column; fund team grid: Collected Amount of unverified rows
      totals[:under_verification] += got.truncate unless verified
      totals[:due] += row_due
      next unless status == "Overdue"

      totals[:overdue] += row_due
      totals[:overdue_count] += 1
    end

    totals.merge(called: totals[:due] + totals[:collected])
  end

  # The LP's view (verified basis) - LP fund page and the commitment card's Due Amount
  def self.lp_totals(scope)
    grid_totals(scope, verified_basis: true)
  end

  # Whether the interactive Verify action should be disabled because nothing has been
  # collected yet while money is actually owed. A remittance with a legitimately zero
  # call_amount (e.g. call_basis_account_entry uploads) still has due_amount <= 0 and is
  # NOT blocked here — see #set_status, which already treats that as "Paid".
  def no_payment_received?
    due_amount.positive? && collected_amount_cents.zero?
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
    # notification_sent is whitelisted so the remittance search page can be filtered down to
    # exactly the investors to change before running the bulk "Mark Notification Sent / Unsent"
    # actions — see CapitalRemittanceSetNotificationSent.
    %w[call_amount collected_amount capital_fee other_fee folio_id investor_name payment_date remittance_date status verified notification_sent arrear_amount fund_id capital_call_id capital_commitment_id].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[capital_call capital_commitment fund investor capital_call]
  end

  after_destroy :touch_investor
  # rubocop:disable Rails/SkipsModelValidations
  # This is to bust any cached dashboards showing the commitments
  def touch_investor
    investor.investor_entity&.touch
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

  # The name of the fee i.e investment_amount, capital_fee or other_fee
  def build_fee_structs(fee_name)
    fee_data = json_fields[fee_name]
    return [] if fee_data.blank?

    fee_data.flatten(1).map do |(name, date, amount)|
      FeeEntry.new(name:, date: Date.parse(date), amount: amount.to_f)
    end.sort_by(&:name)
  end

  def consolidate_fees(fees)
    grouped = fees.group_by(&:name)

    grouped.sort.map do |name, rows|
      ConsolidatedFee.new(name:, amount: Money.new(rows.sum(&:amount)), date: nil) # or pick earliest/latest (see below)
    end
  end

  # Units that must be deleted before this record can be (see BlocksDestroyWithFundUnits)
  def allocated_fund_units
    fund_units
  end
end
