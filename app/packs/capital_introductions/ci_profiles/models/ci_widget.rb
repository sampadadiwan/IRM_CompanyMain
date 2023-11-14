class CiWidget < ApplicationRecord
  belongs_to :ci_profile
  belongs_to :entity

  validates :title, presence: true
  validates :details, presence: true

  include FileUploader::Attachment(:image)
end
