class CiWidget < ApplicationRecord
  belongs_to :ci_profile
  belongs_to :entity

  include FileUploader::Attachment(:image)
end
