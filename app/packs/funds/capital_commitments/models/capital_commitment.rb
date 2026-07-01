class CapitalCommitment < ApplicationRecord
  include Workflowable
  include WithFolder
  include WithExchangeRate
  include WithCustomField
  include Trackable.new
  include CommitmentDocuments
  include WithNextSteps
  include RansackerAmounts.new(fields: %w[committed_amount collected_amount call_amount distribution_amount total_units_amount])

  include ForInvestor
  include WithFriendlyId
  include WithIncomingEmail
  include CapitalCommitmentShared

  # Set by import upload when importing commitments
  attr_accessor :imported

  STANDARD_COLUMNS = { "Folio; text-col" => "folio_id; text-col",
                       "Stakeholder; text-col" => "investor_name; text-col",
                       "Investing Entity; text-col" => "investor_kyc_full_name; text-col",
                       "Unit Type; text-col" => "unit_type; text-col",
                       "Fund Close; text-col" => "fund_close; text-col",
                       "Committed; num-col" => "committed_amount; num-col",
                       "Called; num-col" => "call_amount; num-col",
                       "Collected; num-col" => "collected_amount; num-col",
                       "Distributed; num-col" => "distribution_amount; num-col" }.freeze

  ADDITIONAL_COLUMNS = {
    "Tracking Committed; num-col" => "tracking_committed_amount; num-col",
    "Tracking Collected; num-col" => "tracking_collected_amount; num-col",
    "Tracking Distributed; num-col" => "tracking_distribution_amount; num-col",
    "Tracking Adjusted; num-col" => "tracking_adjustment_amount; num-col",
    "Folio Committed; num-col" => "folio_committed_amount; num-col"
  }.freeze

  ADDITIONAL_COLUMNS_FROM = %w[investor_kyc investor].freeze

  INVESTOR_TAB_STANDARD_COLUMNS = {
    "Fund Name; text-col" => "fund_name; text-col",
    "Investing Entity; text-col" => "investor_kyc_full_name; text-col",
    "Folio; text-col" => "folio_id; text-col"
  }.merge(
    STANDARD_COLUMNS.slice(*STANDARD_COLUMNS.keys - ["Fund Close; text-col", "Stakeholder; text-col", "Investing Entity; text-col", "Folio; text-col"])
  ).freeze

  INVESTOR_STANDARD_COLUMNS = STANDARD_COLUMNS.except("Stakeholder; text-col", "Fund Close; text-col").freeze

  update_index('capital_commitment') { self if index_record? }

  belongs_to :entity
  belongs_to :investor
  belongs_to :investor_kyc, optional: true
  acts_as_list scope: :fund, column: :ppm_number

  belongs_to :fund, touch: true

  # If this is the commitment of a feeder fund, it will have a ref to the feeder_fund
  belongs_to :feeder_fund, class_name: "Fund", optional: true

  # The allocated expenses and incomes
  has_many :account_entries, dependent: :destroy
  # The remitances linked to this commitment
  has_many :capital_remittances, dependent: :destroy
  has_many :capital_remittance_payments, through: :capital_remittances
  # The distributions linked to this commitment
  has_many :capital_distribution_payments, dependent: :destroy
  # The fund units issued to this commitment
  has_many :fund_units, dependent: :destroy
  # Fund ratios computed per investor
  has_many :fund_ratios, dependent: :destroy
  has_many :commitment_adjustments, dependent: :destroy

  belongs_to :investor_signatory, class_name: "User", optional: true

  counter_culture :fund

  monetize :tracking_committed_amount_cents, :tracking_orig_committed_amount_cents, :tracking_adjustment_amount_cents,
           :tracking_distribution_amount_cents, :tracking_collected_amount_cents,
           with_currency: ->(i) { i.fund.tracking_currency.presence || i.fund.currency }

  monetize :orig_folio_committed_amount_cents, :folio_committed_amount_cents,
           :folio_collected_amount_cents, :adjustment_folio_amount_cents,
           with_currency: ->(i) { i.folio_currency.presence || i.fund.currency }

  monetize :orig_committed_amount_cents, :committed_amount_cents, :collected_amount_cents,
           :call_amount_cents, :distribution_amount_cents, :total_units_premium_cents, :total_units_amount_cents, :other_fee_cents, :total_allocated_expense_cents, :total_allocated_income_cents, :adjustment_amount_cents,
           with_currency: ->(i) { i.fund.currency }

  validates :folio_committed_amount_cents, :orig_folio_committed_amount_cents, numericality: { greater_than_or_equal_to: 0 }
  # validates :committed_amount_cents, numericality: { greater_than_or_equal_to: :collected_amount_cents }

  validates :folio_id, :fund_close, :commitment_date, presence: true
  # validates :commitment_date, presence: true, if: proc { |c| c.new_record? }
  validates_uniqueness_of :folio_id, scope: :fund_id

  validates :unit_type, :folio_id, length: { maximum: 40 }
  validates :folio_currency, length: { maximum: 5 }
  validates :virtual_bank_account, length: { maximum: 20 }
  normalizes :unit_type, with: ->(unit_type) { unit_type.strip.squeeze(" ") }
  validate :allowed_unit_type
  validate :allowed_feeder_fund, if: proc { |c| c.feeder_fund_id.present? }

  normalizes :esign_emails, with: ->(v) { v&.gsub(/\s+/, '') }
  validate :esign_emails_must_be_valid, if: -> { esign_emails.present? }

  delegate :currency, to: :fund

  # This is used to compute the total units amount minus collected amount
  # To generate a report where we have collected money but not generated corr units
  # in such case units_amount_minus_collected < 0 from the search screen
  ransacker :units_amount_minus_collected, formatter: proc { |v| v } do |parent|
    Arel::Nodes::SqlLiteral.new(
      "(#{parent.table.name}.total_units_amount_cents - #{parent.table.name}.collected_amount_cents)"
    )
  end

  # Ransacker to check if folio_currency is different from fund.currency
  ransacker :foreign_currency_commitment, formatter: proc { |v| ActiveRecord::Type::Boolean.new.cast(v) } do |parent|
    Arel::Nodes::SqlLiteral.new(
      "CASE WHEN #{parent.table.name}.folio_currency != (SELECT funds.currency FROM funds WHERE funds.id = #{parent.table.name}.fund_id) THEN TRUE ELSE FALSE END"
    )
  end

  counter_culture :fund,
                  column_name: 'committed_amount_cents',
                  delta_column: 'committed_amount_cents',
                  execute_after_commit: true
  # Add the counters for the investor kyc.
  counter_culture :investor_kyc,
                  column_name: 'committed_amount_cents',
                  delta_column: 'committed_amount_cents',
                  execute_after_commit: true

  before_save :set_investor_name
  def set_investor_name
    self.investor_name = investor.investor_name
  end

  def allowed_unit_type
    return unless unit_type

    errors.add(:unit_type, "#{unit_type} is not allowed. Allowed values: #{fund.unit_types}") unless fund.unit_types&.split(",")&.map { |x| x.strip.downcase }&.include?(unit_type&.to_s&.downcase)
  end

  def allowed_feeder_fund
    errors.add(:feeder_fund_id, "The feeder fund #{feeder_fund} must be a feeder fund of the fund #{fund}") if feeder_fund && feeder_fund.master_fund_id != fund_id
  end

  # Note for manual updates to committed amounts
  # 1. Never update the committed_amount_cents directly
  # 2. First set orig_folio_committed_amount_cents & then set the folio_committed_amount_cents
  # 3. Then save it - this will cause the set_orig_amounts to be called which will set things up correctly
  # This note is only if you are making direct changes to the db
  def manually_set_committed_amount(amount_cents)
    self.orig_folio_committed_amount_cents = amount_cents
    self.folio_committed_amount_cents = amount_cents
    save
    compute_percentage
  end

  # This is only excuted to setup the orig amounts
  # orig_committed_amount is the committed amount in the fund currency when the commitment is setup
  # committed_amount is the committed amount in the fund currency after all adjustments
  # Note this will be called on update also, as now we allow update of amounts for 0$ commitments
  # Sets the original committed amounts for the capital commitment record.
  #
  def set_orig_amounts
    # self.orig_folio_committed_amount_cents = folio_committed_amount_cents - adjustment_folio_amount_cents if folio_committed_amount_cents.positive? && orig_folio_committed_amount_cents.zero?

    # binding.pry if orig_folio_committed_amount_cents != 0

    if orig_committed_amount_cents.zero?
      self.orig_committed_amount_cents = convert_currency(folio_currency, fund.currency,
                                                          orig_folio_committed_amount_cents, commitment_date)

    end
  end

  # This is called to set the committed amount after all adjustments
  def set_committed_amount
    # Since the commitment amount is always in the folio currency, we compute te converted committed_amount based on exchange rates.
    self.folio_committed_amount_cents = orig_folio_committed_amount_cents + adjustment_folio_amount_cents
    self.committed_amount_cents = if foreign_currency?
                                    orig_committed_amount_cents + adjustment_amount_cents
                                  else
                                    folio_committed_amount_cents
                                  end
  end

  def commitment_pending
    committed_amount - collected_amount
  end

  def due_amount
    call_amount - collected_amount + other_fee
  end

  def changed_committed_amount_at_exchange_rate(date)
    if get_exchange_rate(folio_currency, fund.currency, date - 1.day).nil?
      0
    else
      convert_currency(folio_currency, fund.currency, folio_pending_committed_amount.cents, date) - convert_currency(folio_currency, fund.currency, folio_pending_committed_amount.cents, date - 1.day)
    end
  end

  def folio_pending_committed_amount
    folio_committed_amount - folio_collected_amount
  end

  after_destroy :compute_percentage
  def compute_percentage
    total_committed_amount_cents = fund.capital_commitments.sum(:committed_amount_cents)
    if total_committed_amount_cents.zero?
      fund.capital_commitments.update_all(percentage: 0)
    else
      fund.capital_commitments.update_all("percentage=100.0*committed_amount_cents/#{total_committed_amount_cents}")
    end
  end

  def foreign_currency?
    folio_currency != fund.currency
  end

  def investor_signatories
    esign_emails&.split(",")&.map(&:strip)
  end

  delegate :fund_signatories, to: :fund
  delegate :ratio_formulas, to: :fund

  def to_s
    if investor_kyc.present?
      "#{investor_kyc.full_name} - #{folio_id}"
    else
      "#{investor_name}, Folio: #{folio_id}"
    end
  end

  # Workflowable interface uses all defaults from the concern:
  #   workflow_display_name → to_s
  #   workflow_url          → capital_commitment_path(self)
  #   workflow_attachable_files → []

  def for_friendly_id
    "#{folio_id}-#{id}"
  end

  ################# eSign stuff follows ###################

  def fund_ratio(name, end_date)
    fund_ratios.where(name:, end_date: ..end_date).last
  end

  # The folio id is used in the folder names of commitments, remittances and distributions
  def update_folio_id
    # Only make changes if this is not a new record
    unless previous_changes[:folio_id].include?(nil) || destroyed?
      document_folder.update_columns(name: folder_name, full_path: folder_path)
      capital_remittances.update_all(folio_id:)
      capital_distribution_payments.update_all(folio_id:)
      account_entries.update_all(folio_id:)

      capital_remittances.each do |cr|
        cr.document_folder.update_columns(full_path: cr.folder_path)
        cr.reload
        cr.document_folder.update_columns(name: cr.folder_name)
      end

      capital_distribution_payments.each do |cdp|
        cdp.document_folder.update_columns(full_path: cdp.folder_path)
        cdp.reload
        cdp.document_folder.update_columns(name: cdp.folder_name)
      end
    end
  end

  # after_commit :touch_investor, unless: :destroyed?
  # This is to bust any cached dashboards showing the commitments
  def touch_investor
    investor.investor_entity&.touch
    entity&.touch
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[created_at updated_at folio_id commitment_date fund_close investor_name onboarding_completed percentage unit_type committed_amount collected_amount call_amount distribution_amount esign_emails folio_currency total_units_amount units_amount_minus_collected foreign_currency_commitment fund_id investor_id investor_kyc_id].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[fund investor investor_kyc commitment_adjustments]
  end

  def cc
    properties["cc"]
  end

  def soa_folder
    get_or_create_folder("Investor Statements", AccessRight.new(entity_id:, access_to_investor_id: investor_id))
  end

  def grant_access_to_fund
    AccessRight.create(entity_id:, owner: fund, investor:, access_type: "Fund", metadata: "Investor")
  end

  def skip_doc_gen?
    json_fields["skip_doc_gen"].to_s.strip.downcase == "yes"
  end
end
