class CapitalCommitment < ApplicationRecord
  include WithFolder
  include WithCustomField
  include Trackable
  include ActivityTrackable
  tracked owner: proc { |_controller, model| model.fund }, entity_id: proc { |_controller, model| model.entity_id }

  include FundScopes

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

  belongs_to :investor_signatory, class_name: "User", optional: true

  has_many :adhaar_esigns, as: :owner
  has_many :esigns, -> { order("sequence_no asc") }, as: :owner
  has_many :signature_workflows, as: :owner

  monetize :committed_amount_cents, :collected_amount_cents,
           :call_amount_cents, :distribution_amount_cents, :total_units_premium_cents,
           :total_allocated_expense_cents, :total_allocated_income_cents,
           with_currency: ->(i) { i.fund.currency }

  validates :committed_amount_cents, numericality: { greater_than: 0 }
  validates :folio_id, presence: true
  validates_uniqueness_of :folio_id, scope: :fund_id

  delegate :currency, to: :fund

  counter_culture :fund, column_name: 'committed_amount_cents', delta_column: 'committed_amount_cents'

  before_save :set_investor_name
  def set_investor_name
    self.investor_name = investor.investor_name
    self.unit_type = unit_type.strip if unit_type
  end

  after_create_commit :create_remittance
  def create_remittance
    # When the CapitalCommitment is created, ensure that for any capital calls prev created
    # The corr CapitalRemittance are created
    CapitalCommitmentRemittanceJob.perform_later(id)
  end

  after_save :compute_percentage, if: :saved_change_to_committed_amount_cents?
  def compute_percentage
    total_committed_amount_cents = fund.capital_commitments.sum(:committed_amount_cents)
    fund.capital_commitments.update_all("percentage=100.0*committed_amount_cents/#{total_committed_amount_cents}")
  end

  def to_s
    "#{investor_name}, Folio: #{folio_id}, Committed: #{committed_amount}"
  end

  def folder_path
    "#{fund.folder_path}/Commitments/#{investor.investor_name.delete('/')}-#{folio_id.delete('/')}"
  end

  def document_list
    # fund.commitment_doc_list&.split(",")
    docs = fund.documents.where(template: true).map { |d| ["#{d.name} Header", "#{d.name} Footer"] }.flatten
    docs += fund.commitment_doc_list.split(",").map(&:strip) if fund.commitment_doc_list.present?
    docs + ["Other"] if docs.present?
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
    addable = account_entries.where(entry_type:, cumulative: false)
    addable = addable.where(name:) if name
    cum_amount_cents = addable.sum(:amount_cents)

    # Create a new Cumulative entry
    new_name = name || entry_type
    ae = account_entries.new(name: new_name, entry_type:, amount_cents: cum_amount_cents, entity_id:, fund_id:, investor_id:, folio_id:, reporting_date: end_date, period: "As of #{end_date}", cumulative: true, generated: true)

    ae.save!
  end

  def cumulative_account_entry(name, entry_type, start_date, end_date)
    cae = account_entries.where(reporting_date: start_date.., cumulative: true).where(reporting_date: ..end_date)
    cae = cae.where(name:) if name
    cae = cae.where(entry_type:) if entry_type
    cae.last || AccountEntry.new(name:, amount_cents: 0)
  end
end
