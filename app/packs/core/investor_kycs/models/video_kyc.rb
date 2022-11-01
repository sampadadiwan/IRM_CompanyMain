class VideoKyc < ApplicationRecord
  has_one_attached :file

  belongs_to :user
  belongs_to :investor_kyc
  belongs_to :entity
end
