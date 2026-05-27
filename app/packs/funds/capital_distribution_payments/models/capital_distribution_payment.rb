class CapitalDistributionPayment < ApplicationRecord
  # Value objects for fee breakdown data passed to Sablon document templates.
  FeeEntry = Data.define(:name, :date, :amount, :fee_type)    # one raw fee line from ae_audit JSON — immutable, fully known at construction
  # Struct (not Data.define) because total_amount_across_folios is annotated in a second pass
  # by the doc generator after consolidation, so the object must be mutable.
  ConsolidatedFee = Struct.new(:name, :amount, :date, :total_amount_across_folios, keyword_init: true) do
    def initialize(name:, amount:, date:, total_amount_across_folios: nil) = super
  end
  include WithCustomField
  include WithExchangeRate
  include Trackable.new
  include CapitalDistributionFees
  include RansackerAmounts.new(fields: %w[income cost_of_investment cost_of_investment_with_fees folio_amount net_of_account_entries net_payable income_with_fees reinvestment reinvestment_with_fees gross_payable gross_of_account_entries tracking_net_payable tax_with_fees expense_with_fees display_only_with_fees])

  include WithFolder

  STANDARD_COLUMNS = { "Stakeholder; text-col" => "investor_name; text-col",
                       "Folio No; text-col" => "folio_id; text-col",
                       "Gross Payable; num-col" => "gross_payable; num-col",
                       "Net Payable; num-col" => "net_payable; num-col",
                       "Payment Date; date-col" => "payment_date; date-col",
                       "Completed; text-col" => "completed; text-col" }.freeze

  INVESTOR_STANDARD_COLUMNS = { "Distribution Name; text-col" => "distribution_name; text-col",
                                "Folio No; text-col" => "folio_id; text-col",
                                "Gross Payable; num-col" => "gross_payable; num-col",
                                "Net Payable; num-col" => "net_payable; num-col",
                                "Payment Date; date-col" => "payment_date; date-col",
                                "Completed; text-col" => "completed; text-col" }.freeze

  include ForInvestor
  include CapitalDistributionPaymentShared

  update_index('capital_distribution_payment') { self if index_record? }

  belongs_to :fund, touch: true
  belongs_to :entity
  belongs_to :capital_distribution, touch: true
  has_many :fund_units, as: :owner, dependent: :destroy

  belongs_to :investor
  belongs_to :capital_commitment
  has_one :investor_kyc, through: :capital_commitment
  has_many :noticed_events, as: :record, dependent: :destroy, class_name: "Noticed::Event"

  monetize :tracking_net_payable_cents, :tracking_gross_payable_cents, :tracking_reinvestment_with_fees_cents, with_currency: ->(i) { i.fund.tracking_currency.presence || i.fund.currency }
  # Note that cost_of_investment_cents is Face value for redemption
  monetize :folio_amount_cents, :net_of_account_entries_cents, with_currency: ->(i) { i.capital_commitment&.folio_currency || i.fund.currency }
  monetize :income_cents, :income_with_fees_cents, :cost_of_investment_cents, :net_payable_cents, :gross_payable_cents, :cost_of_investment_with_fees_cents, :reinvestment_cents, :reinvestment_with_fees_cents, :gross_of_account_entries_cents, :tax_with_fees_cents, :expense_with_fees_cents, :display_only_with_fees_cents, with_currency: ->(i) { i.fund.currency }

  validates :folio_id, presence: true
  validates_uniqueness_of :folio_id, scope: :capital_distribution_id

  validates :folio_id, length: { maximum: 40 }
  validates :investor_name, length: { maximum: 255 }

  counter_culture :capital_distribution,
                  column_name: proc { |r| r.completed ? 'completed_distribution_amount_cents' : nil },
                  delta_column: 'net_payable_cents',
                  column_names: lambda {
                    {
                      CapitalDistributionPayment.completed => :completed_distribution_amount_cents
                    }
                  }

  counter_culture :capital_distribution,
                  column_name: 'distribution_amount_cents',
                  delta_column: 'net_payable_cents'

  counter_culture :capital_distribution,
                  column_name: 'gross_amount_cents',
                  delta_column: 'gross_payable_cents'

  counter_culture :fund,
                  column_name: 'distribution_amount_cents',
                  delta_column: 'gross_payable_cents'

  counter_culture :fund,
                  column_name: proc { |r| r.completed ? 'tracking_distribution_amount_cents' : nil },
                  delta_column: 'tracking_net_payable_cents',
                  column_names: lambda {
                    {
                      CapitalDistributionPayment.completed => :tracking_distribution_amount_cents
                    }
                  }

  counter_culture :capital_commitment,
                  column_name: 'distribution_amount_cents',
                  delta_column: 'gross_payable_cents'

  counter_culture :capital_commitment,
                  column_name: 'tracking_distribution_amount_cents',
                  delta_column: 'tracking_net_payable_cents'

  counter_culture %i[capital_commitment investor_kyc],
                  column_name: 'distribution_amount_cents',
                  delta_column: 'gross_payable_cents'

  scope :has_cost_of_investment, -> { where("cost_of_investment_cents > 0") }
  scope :has_income, -> { where("income_cents > 0") }

  scope :incomplete, -> { where(completed: false) }
  scope :notification_sent, -> { where(notification_sent: true) }
  scope :notification_not_sent, -> { where(notification_sent: false) }

  before_validation :ensure_commitment
  def ensure_commitment
    self.capital_commitment = fund.capital_commitments.where(investor_id:, folio_id:).first
  end

  # before_save :set_investor_name
  def set_investor_name
    self.investor_name = investor.investor_name
  end

  # before_save :set_net_payable, if: :net_payable_cents_changed?
  def set_net_payable
    # Since the distribution amount is always in the fund currency, we compute te converted folio_amount based on exchange rates.
    self.folio_amount_cents = convert_currency(fund.currency, capital_commitment.folio_currency,
                                               net_payable_cents, payment_date)
  end

  # rubocop:disable Rails/SkipsModelValidations
  def send_notification(force: false)
    msg = nil

    if force || !notification_sent
      # Dont send notification if notice generation is skipped
      if completed && capital_distribution.send_notification_on_complete &&
         capital_distribution.approved && !capital_distribution.manual_generation && !capital_commitment.skip_call_notice?

        investor.notification_users(fund).each do |user|
          CapitalDistributionPaymentNotifier.with(record: self, entity_id:, email_method: :send_notification).deliver_later(user)
        end

        update_column(:notification_sent, true)
        msg = "Notification sent for Distribution Payment #{id}"
      else
        msg = "Conditions not met for sending notification for Distribution Payment #{id}"
        msg += " (not completed)" unless completed
        msg += " (notification on complete not set)" unless capital_distribution.send_notification_on_complete
        msg += " (capital distribution not approved)" unless capital_distribution.approved
        msg += " (manual generation)" if capital_distribution.manual_generation
        msg += " (skip call notice)" if capital_commitment.skip_call_notice?
      end
    else
      msg = "Skipping notification for Distribution Payment #{id} as it is already sent."
    end
    Rails.logger.debug { msg }

    msg
  end
  # rubocop:enable Rails/SkipsModelValidations

  # after_commit :update_investor_entity
  # rubocop:disable Rails/SkipsModelValidations
  # This is to bust any cached dashboards showing the commitments
  def update_investor_entity
    investor.investor_entity&.touch
  end
  # rubocop:enable Rails/SkipsModelValidations

  def to_s
    if completed
      "#{investor_name}: #{net_payable} : Completed"
    else
      "#{investor_name}: #{net_payable} : Pending"
    end
  end

  def folder_path
    "#{capital_distribution.folder_path}/#{investor.investor_name.delete('/')}-#{folio_id.delete('/')}"
  end

  def management_fees_days(start_date, end_date)
    if capital_distribution.distribution_date <= start_date
      (end_date - start_date).to_i + 1
    elsif capital_distribution.distribution_date <= end_date
      (end_date - capital_distribution.distribution_date).to_i + 1
    else
      0
    end
  end

  def tracking_exchange_rate_date
    payment_date
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[created_at updated_at folio_id payment_date investor_name completed income cost_of_investment cost_of_investment_with_fees folio_amount net_of_account_entries net_payable income_with_fees reinvestment reinvestment_with_fees gross_payable gross_of_account_entries tracking_net_payable units_quantity percentage fund_id capital_commitment_id].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[fund capital_distribution investor capital_commitment]
  end

  # Builds an array of OpenStructs with name, date, amount and fee_type. It also sorts the fees by name to have a consistent order in the notice.
  def build_fee_structs
    fee_data = json_fields["ae_audit"]
    return [] if fee_data.blank?

    fee_data.flatten(1).map do |(name, date, amount, fee_type)|
      FeeEntry.new(name:, date: Date.parse(date), amount: amount.to_f, fee_type:)
    end.sort_by(&:name)
  end

  # Groups the fees by fee type
  def self.group_by_fee_type(fees)
    fees.group_by(&:fee_type)
  end

  # We will be consolidating the AEs by name for each fee type
  # This is to show the total fees for each fee type in the notice at
  # distribution level (all distribution payments of the distribution),
  # kyc level (all distribution payments of the distribution with the SAME KYC),
  # and folio level (current payment)
  def self.consolidate_fees(fees)
    grouped = fees.group_by(&:name)

    grouped.sort.map do |name, rows|
      ConsolidatedFee.new(name:, amount: Money.new(rows.sum(&:amount)), date: rows.map(&:date).max) # TODO: Discuss if latest date is ok
    end
  end
end
