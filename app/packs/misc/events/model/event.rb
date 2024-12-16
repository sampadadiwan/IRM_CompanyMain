class Event < ApplicationRecord
  belongs_to :owner, polymorphic: true
  belongs_to :user
  belongs_to :entity
  # Tasks associated with this event
  has_many :tasks, as: :owner, dependent: :destroy

  validates :title, presence: true
  validates :start_time, presence: true

  scope :upcoming_events, -> { where('start_time > ?', Time.zone.now) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[owner_type]
  end

  after_create_commit :create_task
  def create_task
    Task.create!(details: title, entity_id:, for_entity_id: entity_id, owner: self, due_date: end_time.to_date, user_id:)
  end

  def to_s
    "#{title} (#{start_time})"
  end
end
