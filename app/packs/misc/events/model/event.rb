class Event < ApplicationRecord
  belongs_to :owner, polymorphic: true

  validates :title, presence: true
  validates :start_time, presence: true

  def self.ransackable_attributes(_auth_object = nil)
    %w[owner_type]
  end
end
