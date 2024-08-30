class CiWidget < ApplicationRecord
  belongs_to :owner, polymorphic: true
  belongs_to :investment_opportunity, optional: true
  belongs_to :entity

  validates :title, presence: true

  include FileUploader::Attachment(:image)
end
