class CiWidget < ApplicationRecord
  belongs_to :investment_opportunity
  belongs_to :entity

  validates :title, presence: true
  validates :details, presence: true

  include FileUploader::Attachment(:image)
end
