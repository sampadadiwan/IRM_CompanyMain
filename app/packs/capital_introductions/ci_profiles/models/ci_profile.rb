class CiProfile < ApplicationRecord
  include WithFolder
  include WithCustomField
  include Trackable

  serialize :track_record, type: Hash

  belongs_to :entity
  belongs_to :fund, optional: true

  has_many :ci_widgets, dependent: :destroy
  has_many :ci_track_records, dependent: :destroy

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
end
