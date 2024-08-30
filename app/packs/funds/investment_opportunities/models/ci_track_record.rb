class CiTrackRecord < ApplicationRecord
  belongs_to :owner, polymorphic: true
  belongs_to :investment_opportunity, optional: true
  belongs_to :entity

  validates :prefix, length: { maximum: 5 }
  validates :suffix, length: { maximum: 5 }
  validates :name, length: { maximum: 50 }
  validates :name, presence: true
  validates :value, presence: true

  def to_s
    "#{prefix} #{value} #{suffix}"
  end
end
