class CapitalCommitment < ApplicationRecord
  include WithFolder
  include WithExchangeRate
  include WithCustomField
  include Trackable.new
  include Memoized
  include CommitmentAccountEntry
  include CommitmentDocuments
  include RansackerAmounts.new(fields: %w[committed_amount collected_amount call_amount distribution_amount])

  include ForInvestor
  include WithFriendlyId
  include WithIncomingEmail

  # Set by import upload when importing commitments
  attr_accessor :imported

  STANDARD_COLUMN_NAMES = ["Type", "Folio", "Investor", "Investing Entity", "Unit Type", "Committed", "Percentage",
                           "Called", "Collected", "Distributed", " "].freeze
  STANDARD_COLUMN_FIELDS = %w[commitment_type folio_id investor_name full_name unit_type committed_amount
                              percentage call_amount collected_amount distribution_amount dt_actions].freeze

  INVESTOR_COLUMN_NAMES = ["Folio", "Investing Entity", "Unit Type", "Committed", "Called",
                           "Collected", "Distributed", " "].freeze
  INVESTOR_COLUMN_FIELDS = %w[folio_id full_name unit_type committed_amount call_amount
                              collected_amount distribution_amount dt_actions].freeze

  COMMITMENT_TYPES = %w[Pool CoInvest].freeze
  enum :commitment_type, { Pool: "Pool", CoInvest: "CoInvest" }
  scope :pool, -> { where(commitment_type: 'Pool') }
  scope :co_invest, -> { where(commitment_type: 'CoInvest') }

  update_index('capital_commitment') { self if index_record? }

  scope :lp_onboarding_complete, -> { where(onboarding_completed: true) }
  scope :lp_onboarding_incomplete, -> { where(onboarding_completed: false) }

  belongs_to :entity
  belongs_to :investor
  belongs_to :investor_kyc, optional: true
  acts_as_list scope: :fund, column: :ppm_number

  belongs_to :fund, touch: true

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

  monetize :orig_folio_committed_amount_cents, :folio_committed_amount_cents, :folio_collected_amount_cents,
           :adjustment_folio_amount_cents, with_currency: ->(i) { i.folio_currency }
  monetize :orig_committed_amount_cents, :committed_amount_cents, :collected_amount_cents,
           :call_amount_cents, :distribution_amount_cents, :total_units_premium_cents, :other_fee_cents,
           :total_allocated_expense_cents, :total_allocated_income_cents, :adjustment_amount_cents,
           with_currency: ->(i) { i.fund.currency }

  validates :folio_committed_amount_cents, numericality: { greater_than_or_equal_to: 0 }
  # validates :committed_amount_cents, numericality: { greater_than_or_equal_to: :collected_amount_cents }

  validates :folio_id, :fund_close, :commitment_type, presence: true
  validates :commitment_date, presence: true, if: proc { |c| c.new_record? }
  validates_uniqueness_of :folio_id, scope: :fund_id

  validates :commitment_type, length: { maximum: 10 }
  validates :unit_type, length: { maximum: 25 }
  validates :folio_currency, length: { maximum: 5 }
  validates :folio_id, :virtual_bank_account, length: { maximum: 20 }
  normalizes :unit_type, with: ->(unit_type) { unit_type.strip.squeeze(" ") }
  validate :allowed_unit_type

  delegate :currency, to: :fund

  # This is used to improve the performance of the formulas, in allocations
  memoize :get_account_entry, :cumulative_account_entry, :on_date, :quarterly, :since_inception

  counter_culture :fund,
                  column_name: proc { |r| r.Pool? ? 'committed_amount_cents' : 'co_invest_committed_amount_cents' },
                  delta_column: 'committed_amount_cents',
                  column_names: lambda {
                    {
                      pool => 'committed_amount_cents',
                      co_invest => 'co_invest_committed_amount_cents'
                    }
                  }

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

    errors.add(:unit_type, "#{unit_type} is not allowed. Allowed values: #{fund.unit_types}") unless fund.unit_types.include?(unit_type)
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
  end

  def set_orig_amounts
    # This is only excuted once when the commitment is created, to setup the orig amounts
    if orig_folio_committed_amount_cents.zero?
      self.orig_folio_committed_amount_cents = folio_committed_amount_cents
      self.orig_committed_amount_cents = convert_currency(folio_currency, fund.currency,
                                                          orig_folio_committed_amount_cents, commitment_date)
    end
  end

  def set_committed_amount
    set_orig_amounts

    # Since the commitment amount is always in the folio currency, we compute te converted committed_amount based on exchange rates.
    self.folio_committed_amount_cents = orig_folio_committed_amount_cents + adjustment_folio_amount_cents
    self.committed_amount_cents = if foreign_currency?
                                    committed_amount_at_exchange_rate
                                  else
                                    folio_committed_amount_cents
                                  end
  end

  def committed_amount_at_exchange_rate
    adjustment_amount_cents + orig_committed_amount_cents
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
    total_committed_amount_cents = fund.capital_commitments.pool.sum(:committed_amount_cents)
    if total_committed_amount_cents.zero?
      fund.capital_commitments.pool.update_all(percentage: 0)
    else
      fund.capital_commitments.pool.update_all("percentage=100.0*committed_amount_cents/#{total_committed_amount_cents}")
    end

    total_committed_amount_cents = fund.capital_commitments.co_invest.sum(:committed_amount_cents)
    if total_committed_amount_cents.zero?
      fund.capital_commitments.co_invest.update_all(percentage: 0)
    else
      fund.capital_commitments.co_invest.update_all("percentage=100.0*committed_amount_cents/#{total_committed_amount_cents}")
    end
  end

  def foreign_currency?
    folio_currency != fund.currency
  end

  def pending_call_amount
    call_amount - collected_amount
  end

  def pending_committed_amount
    committed_amount - collected_amount
  end

  def uncalled_amount
    committed_amount - call_amount
  end

  def percentage_pending_call
    call_amount_cents.positive? ? 100 * (collected_amount_cents / call_amount_cents).round(2) : 0
  end

  def percentage_pending_committed
    committed_amount_cents.positive? ? 100 * (collected_amount_cents / committed_amount_cents).round(2) : 0
  end

  def investor_signatories
    esign_emails&.split(",")&.map(&:strip)
  end

  delegate :fund_signatories, to: :fund

  def to_s
    if investor_kyc.present?
      "#{investor_kyc.full_name} - #{folio_id}"
    else
      "#{investor_name}, Folio: #{folio_id}"
    end
  end

  def for_friendly_id
    "#{folio_id}-#{id}"
  end

  ################# eSign stuff follows ###################

  def fund_ratio(name, end_date)
    fund_ratios.where(name:, end_date: ..end_date).last
  end

  def fund_unit_setting
    fund.fund_unit_settings.where(name: unit_type).last
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
    investor.investor_entity.touch if investor&.investor_entity
    entity&.touch
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[commitment_date commitment_type fund_close investor_name onboarding_completed percentage unit_type committed_amount collected_amount call_amount distribution_amount esign_emails].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[account_entries activities capital_distribution_payments capital_remittance_payments capital_remittances document_folder documents entity exchange_rate folders form_custom_fields form_type fund fund_ratios fund_units investor investor_kyc investor_signatory versions]
  end

  def cc
    properties["cc"]
  end

  def soa_folder
    get_or_create_folder("SOA", AccessRight.new(entity_id:, access_to_investor_id: investor_id))
  end

  def grant_access_to_fund
    AccessRight.create(entity_id:, owner: fund, investor:, access_type: "Fund", metadata: "Investor")
  end

  def committed_amount_cents_before(date)
    date = Date.parse(date) if date.is_a?(String)

    if commitment_date > date
      # If the commitment date is after the date, then there is no commitment before the date
      0
    else
      # Get the top up adjustments before the date
      adjustment_amount_cents_before_date = commitment_adjustments.top_up.where(as_of: ..date).sum(:amount_cents)
      # Get the committed amount before the date
      orig_committed_amount_cents + adjustment_amount_cents_before_date
    end
  end
end
