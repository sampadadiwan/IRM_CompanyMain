# Task model
# entity_id: the entity to which the task belongs (usually the user.entity_id)
# for_entity_id: the user.entity_id, so that both the user (who is logging the task, typically an investor) and the entity (to which the task belongs, typically a fund or deal) can see the task
# However, as per recent changes, both for_entity_id and entity_id default to current_user.entity_id in the controller
# to ensure consistent visibility and simplify link generation.
class Task < ApplicationRecord
  include WithFolder
  include WithCustomField

  CATEGORIES = %w[Finance Ops Compliance IR Other].freeze

  update_index('task') { self if index_record? }
  attr_accessor :send_notification_flag

  has_rich_text :details
  has_rich_text :response

  attr_accessor :action_link, :help_link

  belongs_to :entity
  belongs_to :for_entity, class_name: "Entity", optional: true
  belongs_to :user, optional: true
  belongs_to :assigned_to, class_name: "User", optional: true
  belongs_to :owner, polymorphic: true, optional: true
  belongs_to :task_template, optional: true
  belongs_to :task_recurrence_rule, optional: true

  has_many :noticed_events, as: :record, dependent: :destroy, class_name: "Noticed::Event"

  validates :details, presence: true
  validates :tags, length: { maximum: 50 }
  validates :category, length: { maximum: 40 }, allow_blank: true
  # validates :category, inclusion: { in: CATEGORIES, allow_blank: true }

  has_many :reminders, as: :owner, dependent: :destroy
  accepts_nested_attributes_for :reminders, allow_destroy: true

  scope :completed, -> { where(completed: true) }
  scope :incomplete, -> { where(completed: false) }
  scope :delayed, -> { incomplete.where(due_date: ...Time.zone.today) }
  scope :for_support, -> { where(for_support: true) }
  scope :not_for_support, -> { where(for_support: false) }
  scope :for_category, ->(category) { where(category: category) }

  # counter_culture :entity, column_name: proc { |t| t.completed ? nil : 'tasks_count' }

  after_commit :send_notification, unless: :destroyed?
  def send_notification
    return if task_recurrence_rule_id.present? || send_notification_flag == false

    users = []
    users << user if response.blank?
    users << assigned_to if assigned_to
    users.uniq.compact.each do |u|
      TaskNotifier.with(record: self, entity_id:).deliver_later(u)
    end
  end

  def index_record?
    true
  end

  def folder_path
    # Group tasks by category in the folder structure if available, otherwise general Tasks
    category.present? ? "/Tasks/#{category}" : "/Tasks/General"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[category completed details due_date tags]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[assigned_to user]
  end
end
