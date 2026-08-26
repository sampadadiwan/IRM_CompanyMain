class AccountEntry < ApplicationRecord
  self.primary_key = :id
  # update_index('account_entry') { self if index_record? }

  include WithCustomField
  include ForInvestor
  include Trackable.new(on: [:update])
  include RansackerAmounts.new(fields: %w[amount])
  include AccountEntryShared

  STANDARD_COLUMNS = {
    "ID; num-col" => "id; num-col",
    "Folio; text-col" => "folio_id; text-col",
    "Reporting Date; date-col" => "reporting_date; date-col",
    "Period; text-col" => "period; text-col",
    "For; text-col" => "parent_name; text-col",
    "Entry Type; text-col" => "entry_type; text-col",
    "Name; text-col" => "name; text-col",
    "Amount; num-col" => "amount; num-col"
  }.freeze

  PARENT_TYPES = %w[PortfolioInvestment AggregatePortfolioInvestment Investor AccountEntry].freeze

  belongs_to :capital_commitment, optional: true
  has_one :investor_kyc, through: :capital_commitment
  belongs_to :entity, inverse_of: :account_entries
  belongs_to :fund, inverse_of: :account_entries
  belongs_to :allocation_run, optional: true
  belongs_to :fund_formula, optional: true
  belongs_to :investor, optional: true
  belongs_to :parent, polymorphic: true, optional: true

  monetize :tracking_amount_cents, with_currency: ->(i) { i.fund.tracking_currency.presence || i.fund.currency }
  monetize :folio_amount_cents, with_currency: ->(i) { i.capital_commitment&.folio_currency || i.fund.currency }
  monetize :amount_cents, with_currency: ->(i) { i.fund.currency }

  validates :name, :reporting_date, :entry_type, presence: true
  validates :name, length: { maximum: 125 }
  validates :entry_type, length: { maximum: 60 }
  validates :folio_id, length: { maximum: 40 }, allow_blank: true
  validates :period, length: { maximum: 25 }, allow_blank: true
  validates :name,
            uniqueness: { scope: %i[fund_id capital_commitment_id parent_id parent_type entry_type reporting_date cumulative amount_cents ref_id deleted_at],
                          message: "Duplicate Account Entry for reporting date" }

  scope :for_parent_account_entries, lambda {
    joins("INNER JOIN account_entries AS parent_account_entries ON account_entries.parent_id = parent_account_entries.id AND account_entries.parent_type = 'AccountEntry'")
  }

  def to_s
    "#{name} #{I18n.l(reporting_date)}"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[capital_commitment_id amount cumulative entry_type folio_id generated name period reporting_date allocation_run_id parent_type parent_name parent_id import_upload_id fund_formula_id].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[capital_commitment fund investor allocation_run fund_formula].sort
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

  def self.bulk_update_tracking_currency_numbers(fund, reporting_date)
    exchange_rate = get_exchange_rate(fund.currency, fund.tracking_currency, reporting_date)
    fund.account_entries.where(reporting_date: reporting_date).update_all(tracking_amount_cents: Arel.sql("amount_cents * #{exchange_rate.rate}"))
  end
  # rubocop:enable Rails/SkipsModelValidations

  def tracking_exchange_rate_date
    reporting_date
  end
end
