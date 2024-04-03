class SupportClientMapping < ApplicationRecord
  include Trackable.new
  belongs_to :user
  belongs_to :entity

  def to_s
    "#{user} - #{entity}"
  end
end
