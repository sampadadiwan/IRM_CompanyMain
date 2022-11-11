class CapitalCommitment < ApplicationRecord
  include WithFolder
  include ActivityTrackable
  tracked owner: proc { |_controller, model| model.fund }, entity_id: proc { |_controller, model| model.entity_id }

  belongs_to :entity
  belongs_to :investor
  has_many :investor_kycs, through: :investor

  belongs_to :fund, touch: true
  has_many :capital_remittances, dependent: :destroy
  has_many :documents, as: :owner, dependent: :destroy

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
    parent_folder = fund.document_folder.folders.where(name: "Commitments").first
    setup_folder(parent_folder, investor.investor_name, [])
  end

  scope :for_employee, lambda { |user|
    joins(fund: :access_rights).where("funds.entity_id=? and access_rights.user_id=?", user.entity_id, user.id)
  }

  scope :for_advisor, lambda { |user|
    # Ensure the access rghts for Document
    joins(fund: :access_rights).merge(AccessRight.access_filter)
                               .where("access_rights.metadata=?", "Advisor")
                               .joins(entity: :investors).where("investors.investor_entity_id=?", user.entity_id)
  }
end
