class CapitalCommitment < ApplicationRecord
  include WithFolder
  include ActivityTrackable
  tracked owner: proc { |_controller, model| model.fund }, entity_id: proc { |_controller, model| model.entity_id }

  include FundScopes

  belongs_to :entity
  belongs_to :investor
  has_many :investor_kycs, through: :investor
  acts_as_list scope: :fund, column: :ppm_number

  belongs_to :fund, touch: true
  has_many :capital_remittances, dependent: :destroy
  has_many :documents, as: :owner, dependent: :destroy
  belongs_to :investor_signatory, class_name: "User", optional: true
  belongs_to :form_type, optional: true
  serialize :properties, Hash

  monetize :committed_amount_cents, :collected_amount_cents, with_currency: ->(i) { i.entity.currency }

  validates :committed_amount_cents, numericality: { greater_than: 0 }

  counter_culture :fund, column_name: 'committed_amount_cents', delta_column: 'committed_amount_cents'

  after_create :create_remittance
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

  def setup_folder_details
    setup_folder_from_path("#{fund.folder_path}/Commitments/#{investor.investor_name}-#{id}")
  end

  def investor_signature_types
    self[:investor_signature_types].presence || fund.investor_signature_types
  end
end
