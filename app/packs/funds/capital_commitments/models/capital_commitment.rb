class CapitalCommitment < ApplicationRecord
  include WithFolder
  include WithExchangeRate
  include WithCustomField
  include Trackable
  include ActivityTrackable
  tracked owner: proc { |_controller, model| model.fund }, entity_id: proc { |_controller, model| model.entity_id }

  include ForInvestor

  COMMITMENT_TYPES = %w[Pool CoInvest].freeze
  enum :commitment_type, { Pool: "Pool", CoInvest: "CoInvest" }
  scope :pool, -> { where(commitment_type: 'Pool') }
  scope :co_invest, -> { where(commitment_type: 'CoInvest') }

  update_index('capital_commitment') { self }

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

  belongs_to :investor_signatory, class_name: "User", optional: true

  has_many :adhaar_esigns, as: :owner
  has_many :esigns, -> { order("sequence_no asc") }, as: :owner
  has_many :signature_workflows, as: :owner

  monetize :orig_folio_committed_amount_cents, :folio_committed_amount_cents, :folio_collected_amount_cents,
           :adjustment_folio_amount_cents, with_currency: ->(i) { i.folio_currency }
  monetize :orig_committed_amount_cents, :committed_amount_cents, :collected_amount_cents,
           :call_amount_cents, :distribution_amount_cents, :total_units_premium_cents,
           :total_allocated_expense_cents, :total_allocated_income_cents, :adjustment_amount_cents,
           with_currency: ->(i) { i.fund.currency }

  validates :folio_committed_amount_cents, numericality: { greater_than: 0 }
  # validates :committed_amount_cents, numericality: { greater_than_or_equal_to: :collected_amount_cents }

  validates :folio_id, :fund_close, :commitment_type, presence: true
  validates_uniqueness_of :folio_id, scope: :fund_id

  delegate :currency, to: :fund

  counter_culture :fund,
                  column_name: proc { |r| r.Pool? ? 'committed_amount_cents' : 'co_invest_committed_amount_cents' },
                  delta_column: 'committed_amount_cents',
                  column_names: lambda {
                    {
                      pool => 'committed_amount_cents',
                      co_invest => 'co_invest_committed_amount_cents'
                    }
                  }

  before_save :set_investor_name
  def set_investor_name
    self.investor_name = investor.investor_name
    self.unit_type = unit_type.strip if unit_type
  end

  def set_orig_amounts
    # This is only excuted once when the commitment is created, to setup the orig amounts
    if orig_folio_committed_amount_cents.zero?
      self.orig_folio_committed_amount_cents = folio_committed_amount_cents
      self.orig_committed_amount_cents = convert_currency(folio_currency, fund.currency,
                                                          orig_folio_committed_amount_cents, commitment_date)
    end
  end

  before_save :set_committed_amount
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
    collected_amount_cents + adjustment_amount_cents + convert_currency(folio_currency, fund.currency, folio_pending_committed_amount.cents, Time.zone.today)
  end

  def folio_pending_committed_amount
    folio_committed_amount - folio_collected_amount
  end

  after_create_commit :create_remittance
  def create_remittance
    # When the CapitalCommitment is created, ensure that for any capital calls prev created
    # The corr CapitalRemittance are created
    CapitalCommitmentRemittanceJob.perform_later(id)
  end

  after_destroy :compute_percentage
  after_save :compute_percentage, if: :saved_change_to_committed_amount_cents?
  def compute_percentage
    total_committed_amount_cents = fund.capital_commitments.pool.sum(:committed_amount_cents)
    fund.capital_commitments.pool.update_all("percentage=100.0*committed_amount_cents/#{total_committed_amount_cents}")

    total_committed_amount_cents = fund.capital_commitments.co_invest.sum(:committed_amount_cents)
    fund.capital_commitments.co_invest.update_all("percentage=100.0*committed_amount_cents/#{total_committed_amount_cents}")
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

  def percentage_pending_call
    call_amount_cents.positive? ? 100 * (collected_amount_cents / call_amount_cents).round(2) : 0
  end

  def percentage_pending_committed
    committed_amount_cents.positive? ? 100 * (collected_amount_cents / committed_amount_cents).round(2) : 0
  end

  def to_s
    "#{investor_name}, Folio: #{folio_id}"
  end

  def folder_path
    "#{fund.folder_path}/Commitments/#{investor.investor_name.delete('/')}-#{folio_id.delete('/')}"
  end

  def document_list
    # fund.commitment_doc_list&.split(",")
    docs = fund.documents.where(template: true).map(&:name)
    docs += fund.documents.where(template: true).map { |d| ["#{d.name} Header", "#{d.name} Footer"] }.flatten
    docs += fund.commitment_doc_list.split(",").map(&:strip) if fund.commitment_doc_list.present?
    docs + ["Other"] if docs.present?
    docs.sort
  end

  # Retrieves the templates to be used for rendering as SOA, FRA etc.
  def templates(owner_tag, name = nil)
    fund_templates = fund.documents.where(owner_tag:)
    fund_templates = fund_templates.where(name:) if name
    fund_template_names = fund_templates.pluck(:name)
    # Try and get the template from the capital_commitment which override the fund templates
    commitment_templates = documents.where(name: fund_template_names)

    if commitment_templates.present?
      template_names = commitment_templates.pluck(:name)
      # Get the fund templates that are not overridden by the commitment
      # If a name is specified and we found commitment_templates, then dont get any fund_templates
      fund_templates = name ? [] : fund.documents.where(owner_tag:).where.not(name: template_names)
    end

    commitment_templates + fund_templates
  end

  ################# eSign stuff follows ###################

  def investor_signature_types
    self[:investor_signature_types].presence || fund.investor_signature_types
  end

  def signatory_ids(type = nil)
    if @signatory_ids_map.blank?
      @signatory_ids_map = { adhaar: [], dsc: [] }
      @signatory_ids_map[:adhaar] << investor_signatory_id if investor_signature_types&.include?("adhaar")
      @signatory_ids_map[:adhaar] << fund.fund_signatory_id if fund.fund_signature_types&.include?("adhaar")
      @signatory_ids_map[:adhaar] << fund.trustee_signatory_id if fund.fund_signature_types&.include?("adhaar")
      @signatory_ids_map[:adhaar].compact!
    end
    type ? @signatory_ids_map[type.to_sym] : @signatory_ids_map
  end

  def signature_link(user, document_id = nil)
    # Substitute the phone number required in the link
    CapitalCommitmentEsignProvider.new(self).signature_link(user, document_id)
  end

  def signature_completed(signature_type, document_id, file)
    CapitalCommitmentEsignProvider.new(self).signature_completed(signature_type, document_id, file)
  end

  # In some cases name is nil - Ex Cumulative for portfolio FMV or costs @see AccountEntryAllocationEngine.allocate_portfolio_investments()
  #
  def rollup_account_entries(name, entry_type, start_date, end_date)
    Rails.logger.debug { "rollup_account_entries(#{name}, #{entry_type}, #{start_date}, #{end_date})" }

    # Remove the prev computed cumulative rollups
    deletable = account_entries.where(entry_type:, reporting_date: start_date.., cumulative: true)
    deletable = deletable.where(reporting_date: ..end_date)
    deletable = deletable.where(name:) if name
    deletable.delete_all

    # Find the cum_amount_cents
    addable = account_entries.where(entry_type:, cumulative: false, reporting_date: ..end_date)
    addable = addable.where(name:) if name
    cum_amount_cents = addable.sum(:amount_cents)

    # Create a new Cumulative entry
    new_name = name || entry_type
    ae = account_entries.new(name: new_name, entry_type:, amount_cents: cum_amount_cents, entity_id:, fund_id:, investor_id:, folio_id:, reporting_date: end_date, period: "As of #{end_date}", cumulative: true, generated: true)

    ae.save!
    ae
  end

  def cumulative_account_entry(name, entry_type, start_date, end_date, cumulative: true)
    cae = account_entries.where(cumulative:).order(reporting_date: :asc)
    cae = cae.where(reporting_date: start_date..) if start_date
    cae = cae.where(reporting_date: ..end_date) if end_date
    cae = cae.where(name:) if name
    cae = cae.where(entry_type:) if entry_type

    cae.last || AccountEntry.new(name:, fund_id:, amount_cents: 0)
  end

  def fund_ratio(name, end_date)
    fund_ratios.where(name:, end_date: ..end_date).last
  end
end
