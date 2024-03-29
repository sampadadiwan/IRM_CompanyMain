class FundRatio < ApplicationRecord
  include Trackable.new
  include ForInvestor

  belongs_to :entity
  belongs_to :fund
  belongs_to :capital_commitment, optional: true
  belongs_to :valuation, optional: true
  belongs_to :owner, polymorphic: true, optional: true

  validates :display_value, length: { maximum: 50 }
  validates :name, :owner_type, length: { maximum: 255 }

  scope :latest, -> { where(latest: true) }
end
