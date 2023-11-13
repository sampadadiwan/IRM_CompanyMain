class CiTrackRecord < ApplicationRecord
  belongs_to :ci_profile
  belongs_to :entity

  def to_s
    "#{prefix} #{value} #{suffix}"
  end
end
