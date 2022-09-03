class CapitalCall < ApplicationRecord
  include WithFolder

  belongs_to :entity
  belongs_to :fund

  belongs_to :form_type, optional: true
  serialize :properties, Hash

  has_many :capital_remittances, dependent: :destroy
  has_many :documents, as: :owner, dependent: :destroy

  validates :name, :due_date, :percentage_called, presence: true
  validates :percentage_called, numericality: { in: 0..100 }

  monetize :call_amount_cents, :collected_amount_cents, with_currency: ->(i) { i.entity.currency }

  after_create ->(cc) { CapitalCallJob.perform_later(cc.id) }

  def setup_folder_details
    parent_folder = fund.document_folder.folders.where(name: "Capital Calls").first
    setup_folder(parent_folder, name, [])
  end

  def due_amount
    call_amount - collected_amount
  end

  def percentage_raised
    (collected_amount_cents * 100.0 / call_amount_cents).round(2)
  end

  after_create :notify_capital_call
  def notify_capital_call
    FundMailer.with(id:).notify_capital_call.deliver_later
  end

  def reminder_capital_call
    FundMailer.with(id:).reminder_capital_call.deliver_later
  end

  def self.for_investor(user)
    CapitalCall
      # Ensure the access rghts for Document
      .joins(fund: :access_rights)
      .merge(AccessRight.access_filter)
      .joins(entity: :investors)
      # Ensure that the user is an investor and tis investor has been given access rights
      # .where("entities.id=?", entity.id)
      .where("investors.investor_entity_id=?", user.entity_id)
      # Ensure this user has investor access
      .joins(entity: :investor_accesses)
      .merge(InvestorAccess.approved_for_user(user))
  end
end
