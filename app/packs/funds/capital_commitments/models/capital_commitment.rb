class CapitalCommitment < ApplicationRecord
  include WithFolder
  include ActivityTrackable
  tracked owner: proc { |_controller, model| model.fund }, entity_id: proc { |_controller, model| model.entity_id }

  include FundScopes

  update_index('capital_commitment') { self }

  scope :lp_onboarding_complete, -> { where(onboarding_completed: true) }
  scope :lp_onboarding_incomplete, -> { where(onboarding_completed: false) }

  belongs_to :entity
  belongs_to :investor
  has_many :investor_kycs, through: :investor
  acts_as_list scope: :fund, column: :ppm_number

  belongs_to :fund, touch: true

  # has_many :capital_calls, dependent: :destroy
  has_many :capital_remittances, dependent: :destroy
  has_many :capital_distribution_payments, dependent: :destroy

  has_many :documents, as: :owner, dependent: :destroy
  belongs_to :investor_signatory, class_name: "User", optional: true
  belongs_to :form_type, optional: true
  serialize :properties, Hash

  has_many :adhaar_esigns, as: :owner
  has_many :esigns, -> { order("sequence_no asc") }, as: :owner
  has_many :signature_workflows, as: :owner

  monetize :committed_amount_cents, :collected_amount_cents,
           :call_amount_cents, :distribution_amount_cents, with_currency: ->(i) { i.fund.currency }

  validates :committed_amount_cents, numericality: { greater_than: 0 }
  validates :folio_id, presence: true
  validates_uniqueness_of :folio_id, scope: :fund_id

  counter_culture :fund, column_name: 'committed_amount_cents', delta_column: 'committed_amount_cents'

  after_create_commit :create_remittance
  def create_remittance
    # When the CapitalCommitment is created, ensure that for any capital calls prev created
    # The corr CapitalRemittance are created
    fund.capital_calls.each do |cc|
      CapitalCallJob.perform_later(cc.id)
    end
  end

  after_save :compute_percentage, if: :saved_change_to_committed_amount_cents?
  def compute_percentage
    total_committed_amount_cents = fund.capital_commitments.sum(:committed_amount_cents)
    fund.capital_commitments.update_all("percentage=100.0*committed_amount_cents/#{total_committed_amount_cents}")
  end

  def to_s
    "#{investor.investor_name}: #{committed_amount}"
  end

  def folder_path
    "#{fund.folder_path}/Commitments/#{investor.investor_name}-#{id}"
  end

  def document_list
    # fund.commitment_doc_list&.split(",")
    docs = fund.documents.where(owner_tag: "Template").map { |d| ["#{d.name} Header", "#{d.name} Footer"] }.flatten
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
end
