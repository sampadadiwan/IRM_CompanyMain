class CapitalDistribution < ApplicationRecord
  # Journeys (capital-distribution-journey): auto-assigned on create, evaluated from the data.
  # Worked examples H2, H9 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
  include Workflowable

  # Auto-assignment rules may also test "Imported" — the seeded Light journey rule routes on it.
  # distribution_amount / gross_amount are rolled up from payments after commit (always 0 when the
  # distribution is created, the only time a rule is checked), so they are left out
  workflow_rule_fields extra: %w[manual_generation],
                       except: %w[updated_at distribution_amount gross_amount]
  include WithCustomField
  include Trackable.new

  include WithFolder
  include RansackerAmounts.new(fields: %w[carry cost_of_investment distribution_amount fee gross_amount income reinvestment])

  include ForInvestor
  include WithCustomNotifications
  include CapitalDistributionShared
  include BlocksDestroyWithFundUnits

  # Evergreen settlement records (created by a dealing date) get no journey of their own — the dealing
  # date's journey replaces it. The flag covers the create callback, before the dealing date links it.
  # Backward compatibility B4 — openspec/changes/open-ended-funds/design.md#backward-compatibility
  attr_accessor :evergreen_settlement_flag

  def skip_journey?
    evergreen_settlement_flag || (persisted? && DealingDate.exists?(redemption_distribution_id: id))
  end

  FEE_TYPES = ["Fees Part Of Capital", "Other Fees"].freeze

  belongs_to :fund, touch: true
  belongs_to :entity
  belongs_to :approved_by_user, class_name: "User", optional: true

  has_many :distribution_fees, inverse_of: :capital_distribution, dependent: :destroy
  accepts_nested_attributes_for :distribution_fees, allow_destroy: true

  has_many :capital_distribution_payments, dependent: :destroy, inverse_of: :capital_distribution
  has_many :capital_commitments, through: :capital_distribution_payments
  has_many :investors, through: :capital_distribution_payments
  # These are the PIs whose sale gains were distributed via this CD
  has_many :portfolio_investments

  # Stores the prices for unit types for this call
  serialize :unit_prices, type: Hash

  self.ignored_columns += %w[net_amount_cents]
  # cost_of_investment - this is the FV for Redemption
  # distribution_amount - this what has actually been distributed via payments & marked as completed
  # gross_amount - this is the total amount that has to be distributed
  # reinvestment - This is the amount that is reinvested
  # income - This is the income from sale of portfolio that is to be distributed
  monetize :income_cents, :reinvestment_cents, :gross_amount_cents, :distribution_amount_cents, :completed_distribution_amount_cents, :cost_of_investment_cents, :fee_cents, with_currency: ->(i) { i.fund.currency }

  validates_uniqueness_of :title, scope: :fund_id
  validates :title, presence: true
  normalizes :title, with: ->(title) { title.strip.squeeze(" ") }
  validates :title, length: { maximum: 255 }

  validates :distribution_date, presence: true

  after_create_commit :generate_distribution_payments, unless: :destroyed?

  def generate_distribution_payments
    if generate_payments
      # if the distribution_on is "Upload", we do not generate payments as the payments are also uploaded
      return if distribution_on_upload?

      Rails.logger.debug { "generate_distribution_payments called for #{id}" }
      CapitalDistributionJob.perform_later(id)
    else
      Rails.logger.debug { "Skipping generate_distribution_payments for #{id}, generate_payments is false" }
    end
  end

  def to_s
    title
  end

  def folder_path
    "#{fund.folder_path}/Capital Distributions/#{title.delete('/')}"
  end

  # Falls back to the fund's default CapitalDistribution notification (for_type: "CapitalDistribution")
  # when this specific distribution has no override of its own for the given email_method.
  def custom_notification(email_method, for_type: nil, custom_notification_id: nil)
    super || fund.custom_notification(email_method, for_type: "CapitalDistribution", custom_notification_id:)
  end

  def distribution_percentage(capital_commitment)
    case distribution_on
    when "Commitment Percentage"
      # Commitment Percentage
      capital_commitment.percentage
    when "Investable Capital Percentage"
      # Investable Capital Percentage
      icp_entries = capital_commitment.account_entries.where(name: "Investable Capital Percentage", reporting_date: ..distribution_date)
      per = icp_entries.order(reporting_date: :asc).last
      per.present? ? per.amount_cents / 100.0 : capital_commitment.percentage
    else
      raise "Unknown distribution_on for CD #{id}"
    end
  end

  def fee_account_entry_names
    fund.account_entries.where(entry_type: DistributionFee::TYPES).pluck(:name).uniq << "Other"
  end

  def fund_units
    FundUnit.where(fund_id:, owner_type: "CapitalDistributionPayment", owner_id: capital_distribution_payment_ids)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[approved carry completed cost_of_investment created_at distribution_amount distribution_date distribution_on fee gross_amount income reinvestment title updated_at fund_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[fund]
  end

  ransacker :distribution_on, formatter: lambda { |value|
    # If user passes something like "Upload", map it to 2
    # If user passes the integer, e.g. "2", then it remains "2"
    # So we handle both cases safely
    distribution_ons[value] || value
  } do |parent|
    parent.table[:distribution_on]
  end

  def distribution_on_upload?
    distribution_on == "Upload"
  end

  # The journey panel on the distribution page: real-time refresh, creator as default owner and
  # journey_progress_for all come from Workflowable.
  # Worked examples E16, E17, E18 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
  has_journey

  # Ids of the fund's commitments set to Skip Doc Gen. Memoized: one journey evaluation (and its
  # warnings) asks for it ~10 times, and each lookup plucks json_fields for every commitment.
  # Worked examples E3, E6 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
  def skip_doc_gen_commitment_ids
    @skip_doc_gen_commitment_ids ||= CapitalCommitment.skip_doc_gen_ids(fund.capital_commitments)
  end

  # Drops memoized lookups along with the attributes
  def reload(*)
    @skip_doc_gen_commitment_ids = nil
    super
  end

  # Units that must be deleted before this record can be (see BlocksDestroyWithFundUnits)
  def allocated_fund_units
    FundUnit.where(owner_type: "CapitalDistributionPayment", owner_id: capital_distribution_payments.select(:id))
  end
end
