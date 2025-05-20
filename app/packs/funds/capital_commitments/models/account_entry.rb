class AccountEntry < ApplicationRecord
  # update_index('account_entry') { self if index_record? }

  include WithCustomField
  include WithExchangeRate
  include ForInvestor
  include Trackable.new(on: [:update])
  include RansackerAmounts.new(fields: %w[amount])

  STANDARD_COLUMNS = {
    "Folio" => "folio_id",
    "Reporting Date" => "reporting_date",
    "Period" => "period",
    "For" => "parent_name",
    "Entry Type" => "entry_type",
    "Name" => "name",
    "Amount" => "amount"
  }.freeze

  belongs_to :capital_commitment, optional: true
  belongs_to :entity
  belongs_to :fund
  belongs_to :allocation_run, optional: true
  belongs_to :fund_formula, optional: true
  belongs_to :investor, optional: true
  belongs_to :parent, polymorphic: true, optional: true

  # Account entries come in 2 flavours, they are either accounting entries or reporting entries.
  enum :rule_for, { accounting: "Accounting", reporting: "Reporting" }

  # Used in has_scope of controller
  # Define a scope to filter records by a starting reporting date
  scope :reporting_date_start, ->(reporting_date_start) { where(reporting_date: reporting_date_start..) }

  # Define a scope to filter records by an ending reporting date
  scope :reporting_date_end, ->(reporting_date_end) { where(reporting_date: ..reporting_date_end) }

  # Define a scope to filter records by entry type
  scope :entry_type, ->(entry_type) { where(entry_type:) }

  # Define a scope to filter records by folio ID
  scope :folio_id, ->(folio_id) { where(folio_id:) }

  # Define a scope to filter records by unit type in the capital commitments table
  scope :unit_type, ->(unit_type) { where('capital_commitments.unit_type': unit_type) }

  # Define a scope to filter records that are cumulative
  scope :cumulative, -> { where(cumulative: true) }

  # Define a scope to filter records that are not cumulative
  scope :not_cumulative, -> { where.not(cumulative: true) }

  # Define a scope to filter records that are generated
  scope :generated, -> { where(generated: true) }

  # Define a scope to filter records that are fund entries (i.e., capital_commitment_id is nil)
  scope :fund_entries, -> { where(capital_commitment_id: nil) }

  # This stores the calculation explanation for the account entry
  serialize :explanation, type: Array

  monetize :tracking_amount_cents, with_currency: ->(i) { i.fund.tracking_currency.presence || i.fund.currency }
  monetize :folio_amount_cents, with_currency: ->(i) { i.capital_commitment&.folio_currency || i.fund.currency }
  monetize :amount_cents, with_currency: ->(i) { i.fund.currency }

  validates :name, :reporting_date, :entry_type, presence: true
  validates :name, length: { maximum: 125 }
  validates :name,
            uniqueness: { scope: %i[fund_id capital_commitment_id parent_id parent_type entry_type reporting_date cumulative deleted_at],
                          message: "Duplicate Account Entry for reporting date" }

  before_validation :setup_defaults
  def setup_defaults
    self.period = "Q#{(reporting_date.month / 3.0).ceil}-#{reporting_date.year}"
    self.parent_name = parent.to_s[0..254] if parent.present?
    self.commitment_name = capital_commitment.to_s[0..254] if capital_commitment.present?
  end

  before_save :set_folio_amount, if: :capital_commitment
  def set_folio_amount
    # Since the account entry amount is always in the fund currency, we compute the converted folio_amount based on exchange rates.
    if folio_amount_cents.zero?
      self.folio_amount_cents = convert_currency(fund.currency, capital_commitment.folio_currency,
                                                 amount_cents, reporting_date)
    end
  end

  before_save :setup_rule_for
  def setup_rule_for
    if fund_formula.present?
      # Set rule_for based on the presence and type of fund_formula
      self.rule_for ||= fund_formula.reporting? ? "reporting" : "accounting"
    elsif rule_for.blank? || rule_for.downcase != "reporting"
      self.rule_for = "accounting"
    end
    # Set rule_for to accounting if it is blank or not "reporting"
  end

  def to_s
    "#{name} #{I18n.l(reporting_date)}"
  end

  def self.total_amount(account_entries, name: nil, entry_type: nil, cumulative: false, start_date: nil, end_date: nil)
    account_entries = account_entries.where(entry_type:) if entry_type
    account_entries = account_entries.where(name:) if name
    account_entries = account_entries.where(cumulative:)
    account_entries = account_entries.where(reporting_date: start_date..) if start_date
    account_entries = account_entries.where(reporting_date: ..end_date) if end_date
    account_entries.sum(:amount_cents)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[capital_commitment_id amount cumulative entry_type folio_id generated name period reporting_date allocation_run_id parent_type parent_name].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[capital_commitment fund investor allocation_run]
  end

  def template_field_name
    name.titleize.delete(' :,;').underscore
  end

  def index_reporting_date
    entries_to_index = fund.account_entries.includes(:fund, :entity).where(reporting_date:)
    Rails.logger.debug { "Indexing #{entries_to_index.count} account entries for reporting date #{reporting_date}" }
    entries_to_index.each(&:run_chewy_callbacks)
    Rails.logger.debug { "Indexing completed. #{entries_to_index.count} account entries indexed for reporting date #{reporting_date}" }
  end

  # rubocop:disable Rails/SkipsModelValidations
  def self.bulk_update_tracking_currency_numbers(fund, reporting_date)
    exchange_rate = get_exchange_rate(fund.currency, fund.tracking_currency, reporting_date)
    fund.account_entries.where(reporting_date: reporting_date).update_all(tracking_amount_cents: Arel.sql("amount_cents * #{exchange_rate.rate}"))
  end
  # rubocop:enable Rails/SkipsModelValidations

  def tracking_exchange_rate_date
    reporting_date
  end
end
