class Task < ApplicationRecord
  update_index('task') { self if index_record? }
  include WithCustomField

  has_rich_text :details
  has_rich_text :response

  attr_accessor :action_link, :help_link

  belongs_to :entity
  belongs_to :for_entity, class_name: "Entity", optional: true
  belongs_to :user, optional: true
  belongs_to :assigned_to, class_name: "User", optional: true
  belongs_to :owner, polymorphic: true, optional: true
  belongs_to :task_template, optional: true

  has_many :noticed_events, as: :record, dependent: :destroy, class_name: "Noticed::Event"

  validates :details, presence: true
  validates :tags, length: { maximum: 50 }

  has_many :reminders, as: :owner, dependent: :destroy
  accepts_nested_attributes_for :reminders, allow_destroy: true

  scope :completed, -> { where(completed: true) }
  scope :incomplete, -> { where(completed: false) }
  scope :delayed, -> { incomplete.where(due_date: ...Time.zone.today) }
  scope :for_support, -> { where(for_support: true) }
  scope :not_for_support, -> { where(for_support: false) }

  # counter_culture :entity, column_name: proc { |t| t.completed ? nil : 'tasks_count' }

  after_commit :send_notification, unless: :destroyed?
  def send_notification
    users = []
    users << user if response.blank?
    users << assigned_to if assigned_to
    users.uniq.compact.each do |u|
      TaskNotifier.with(record: self, entity_id:).deliver_later(u)
    end
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[details response tags completed due_date created_at updated_at for_support owner_type owner_id].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[assigned_to owner]
  end

  def self.ransackable_scopes(_auth_object = nil)
    %i[completed incomplete delayed for_support not_for_support]
  end
end
