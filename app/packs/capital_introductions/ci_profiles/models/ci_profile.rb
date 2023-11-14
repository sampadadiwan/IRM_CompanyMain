class CiProfile < ApplicationRecord
  include WithFolder
  include WithCustomField
  include Trackable
  include ForInvestor

  serialize :track_record, type: Hash
  validates :title, :geography, :stage, :details, presence: true
  validates :fund_size_cents, :min_investment_cents, numericality: { greater_than: 0 }

  validates :geography, :stage, :sector, length: { maximum: 50 }
  validates :currency, length: { maximum: 3 }

  belongs_to :entity
  belongs_to :fund, optional: true

  has_many :ci_widgets, dependent: :destroy
  has_many :ci_track_records, dependent: :destroy
  has_many :access_rights, as: :owner, dependent: :destroy

  monetize :fund_size_cents, :min_investment_cents, with_model_currency: ->(i) { i.currency }

  def document_list
    ["Pitch Deck", "Founders Video", "Financials", "Other"]
  end

  def folder_path
    "Capital Introductions/#{id}"
  end

  def to_s
    title
  end

  def name
    title
  end
end
