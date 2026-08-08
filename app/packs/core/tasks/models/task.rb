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
  # LP CRM MVP: the person at the LP this task involves — the contact's
  # InvestorAccess record (assigned_to remains the internal GP user doing the
  # work; touch_point is their counterpart at the LP). See Note#touch_point.
  belongs_to :touch_point, class_name: "InvestorAccess", optional: true
  belongs_to :task_template, optional: true

  # Same guard as Note#touch_point_belongs_to_owner: params are not to be
  # trusted, so a touch point must be a contact of the task's owner stakeholder.
  validate :touch_point_belongs_to_owner, if: -> { touch_point_id.present? }

  def touch_point_belongs_to_owner
    errors.add(:touch_point_id, "is not a contact of this stakeholder") unless owner.is_a?(Investor) && touch_point&.investor_id == owner_id
  end
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

  # Kanban board status (string-backed per codebase convention — see Kpi, DealActivity).
  # Driven only by TasksController#update_status (board drag) and the completed sync
  # below — deliberately NOT in task_params or ransackable_attributes.
  enum :status, { todo: "todo", in_progress: "in_progress", done: "done" }

  # Keep status and the legacy completed flag in sync in BOTH directions:
  # - board drag to/from Done drives completed (checkbox, stats, delayed scope still work)
  # - the completed checkbox / TasksController#completed drives status (card moves on board)
  # Pure assignment (no nested save) => no callback loop. Declared BEFORE
  # stamp_completed_on so the completed_on stamping still sees
  # will_save_change_to_completed? after the sync writes `completed`.
  before_save :sync_status_and_completed, if: -> { will_save_change_to_status? || will_save_change_to_completed? }

  def sync_status_and_completed
    if will_save_change_to_status?
      # Board path wins when both change in one save (only the board sends status)
      self.completed = done?
    elsif completed?
      self.status = "done"
    elsif done?
      # Un-completing a done task sends it back to the To Do column
      self.status = "todo"
    end
  end

  # Every completion route — the list-row checkbox, the form's `completed` box, and
  # TasksController#completed — goes through save, so stamping here covers them all
  # without a new form field.
  before_save :stamp_completed_on, if: :will_save_change_to_completed?
  after_save :register_owner_interaction, if: :saved_change_to_completed_on?

  def stamp_completed_on
    self.completed_on = completed? ? Time.zone.today : nil
  end

  def register_owner_interaction
    return unless completed?

    owner.register_interaction(completed_on) if owner.is_a?(DealInvestor)
    # Duck-typed completion hook: owners that track their own completion
    # side-effects (e.g. SideLetterObligation recording an ObligationFulfillment)
    # implement register_task_completion — keeps core/tasks free of a hard
    # dependency on funds-pack models.
    owner.register_task_completion(self) if owner.respond_to?(:register_task_completion)
  end

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

  # Single source of truth for the "Delayed" badge — instance twin of the
  # `delayed` scope above; used by both the list row and the board card.
  def delayed?
    !completed && due_date.present? && due_date < Time.zone.today
  end

  # Plain-text details for compact displays (kanban cards etc.). Older rows
  # predate ActionText and keep their text only in the legacy `details` column,
  # which has_rich_text hides — self[:details] reads the raw column. That column
  # holds HTML (with entity-encoded fragments), so run it through ActionText's
  # plain-text conversion rather than rendering the markup as literal text.
  def display_details
    details.to_plain_text.presence || ActionText::Content.new(self[:details].to_s).to_plain_text
  end

  def index_record?
    true
  end

  def folder_path
    # Group tasks by category in the folder structure if available, otherwise general Tasks
    category.present? ? "/Tasks/#{category}" : "/Tasks/General"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[category completed completed_on details due_date tags]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[assigned_to user]
  end
end
