class CapitalCall < ApplicationRecord
  include WithFolder

  belongs_to :entity
  belongs_to :fund

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
end
