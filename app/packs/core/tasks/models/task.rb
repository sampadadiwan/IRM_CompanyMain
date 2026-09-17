# Task model
# entity_id: the entity to which the task belongs (usually the user.entity_id)
# for_entity_id: the user.entity_id, so that both the user (who is logging the task, typically an investor) and the entity (to which the task belongs, typically a fund or deal) can see the task
# However, as per recent changes, both for_entity_id and entity_id default to current_user.entity_id in the controller
# to ensure consistent visibility and simplify link generation.
class Task < ApplicationRecord
  include WithFolder
  include WithCustomField

  # "Other" stays last — it is the catch-all that reveals the free-text box in
  # the form. Multi-word entries cannot use %w, hence the explicit array.
  CATEGORIES = ["Finance", "Ops", "Compliance", "IR", "Portfolio Company", "Other"].freeze

  # Quick due-date filter offered on the board and list views (label => param
  # value). Order is display order in the dropdown.
  DUE_FILTERS = {
    "Overdue" => "overdue",
    "Due This Week" => "this_week",
    "Due Next Week" => "next_week",
    "Due This Month" => "this_month",
    "Due Next Month" => "next_month"
  }.freeze

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
  # LP CRM: the person at the LP this task involves — the contact's InvestorAccess
  # record (assigned_to remains the internal GP user doing the work; touch_point
  # is their counterpart at the LP). Available on Investor-owned tasks and on
  # tasks logged under a DealInvestor alike. See WithTouchPoint.
  include WithTouchPoint

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
  # Self-guarding: an unrecognized key returns `all` (no filter) — without the
  # guard, due_filter_range's nil would become where(due_date: nil), silently
  # narrowing to tasks with NO due date.
  scope :due_in, ->(key) { (range = due_filter_range(key)) ? where(due_date: range) : all }

  # Date range for a DUE_FILTERS key, or nil for an unrecognized one — callers
  # skip the where(...) entirely rather than filtering to an empty scope.
  # Weeks/months follow Rails' locale-configured start-of-week; overdue mirrors
  # the `delayed` scope above (due_date strictly before today).
  def self.due_filter_range(key)
    today = Time.zone.today
    case key
    when "overdue" then ...today
    when "this_week" then today.all_week
    when "next_week" then (today + 1.week).all_week
    when "this_month" then today.all_month
    when "next_month" then (today + 1.month).all_month
    end
  end

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

  # Plain-text of the task's "Response" field — the running note/comment a fund user
  # keeps on a task. Used by the weekly digest row. Same legacy fallback as
  # display_details above: rows created before ActionText keep their text in the raw
  # `response` column, which has_rich_text hides, and that column holds HTML.
  def display_response
    response.to_plain_text.presence || ActionText::Content.new(self[:response].to_s).to_plain_text
  end

  # Details as renderable HTML. Rows created before ActionText keep their markup
  # in the legacy `details` column, which has_rich_text hides — so those tasks
  # render blank anywhere `task.details` is used directly, while the kanban card
  # (display_details, which already falls back) shows their text. That mismatch
  # makes the list and the board look like they disagree about the same task.
  # Callers must sanitize the legacy branch: it is old user-entered HTML.
  def details_html
    details.body.present? ? details : self[:details].to_s
  end

  # True when the text comes from the legacy column and still needs sanitizing.
  def legacy_details?
    details.body.blank? && self[:details].present?
  end

  # Label for the list's "For" column. Commitment/PI/API to_s pack in folio ids,
  # instruments and dates — too much for a table cell, so those collapse to just
  # the stakeholder name (the row still links to the full record). Both names
  # are stored columns on their tables, so this adds no queries beyond the
  # owner load the row already does. Every other owner type keeps its to_s.
  def owner_display_name
    case owner
    when CapitalCommitment
      owner.investor_name
    when PortfolioInvestment, AggregatePortfolioInvestment
      owner.portfolio_company_name
    else
      owner&.to_s
    end
  end

  # The four numbers on the tasks dashboard, in one pass over the scope.
  #
  # The partial used to rebuild the scope and run a COUNT inside each card —
  # four policy-scope constructions and four full scans per page render. SUM over
  # CASE rather than a FILTER clause or engine-specific boolean syntax, so the
  # same SQL runs on MySQL (dev/prod) and SQLite (test).
  #
  # reorder(nil) drops ransack's default sort: ordering an aggregate is pointless
  # and some engines reject it outright.
  def self.stat_counts(scope)
    today = Time.zone.today
    completed = "SUM(CASE WHEN tasks.completed THEN 1 ELSE 0 END)"
    incomplete = "SUM(CASE WHEN tasks.completed THEN 0 ELSE 1 END)"
    delayed = sanitize_sql_array(
      ["SUM(CASE WHEN tasks.completed THEN 0 WHEN tasks.due_date < ? THEN 1 ELSE 0 END)", today]
    )
    due_this_week = sanitize_sql_array(
      ["SUM(CASE WHEN tasks.due_date BETWEEN ? AND ? THEN 1 ELSE 0 END)",
       today.beginning_of_week, today.end_of_week]
    )

    values = scope.reorder(nil).pick(
      Arel.sql(completed), Arel.sql(incomplete), Arel.sql(delayed), Arel.sql(due_this_week)
    )
    # pick returns nil when the scope has no rows at all
    values ||= []

    { completed: values[0].to_i, incomplete: values[1].to_i,
      delayed: values[2].to_i, due_this_week: values[3].to_i }
  end

  # The six numbers behind the weekly task digest, in one pass over the scope —
  # same shape and the same portability constraints as stat_counts above.
  #
  # SUM over CASE rather than FILTER or engine-specific boolean syntax, so the identical
  # SQL runs on MySQL (dev/prod) and SQLite (test). The CASE arms lead with
  # `WHEN tasks.completed` so the incomplete branches never need a NOT.
  #
  # Deliberately returns MIN(due_date) rather than an age in days: DATEDIFF is MySQL and
  # julianday is SQLite, and a digest that silently reports different numbers under test
  # than in production is worse than no number. The subtraction happens in Ruby.
  #
  # delayed_window bounds the overdue set — see WeeklyTaskDigest::DELAYED_WINDOW. The
  # `delayed` scope and #delayed? above stay unbounded on purpose; they drive the list
  # row and board card badges, where "overdue" means overdue at all.
  def self.digest_counts(scope, as_of: Time.zone.today, delayed_window: 90.days)
    this_week = as_of.all_week
    last_week = (as_of - 1.week).all_week
    next_week = (as_of + 1.week).all_week
    # Half-open on purpose: a task due today is neither delayed nor part of next week.
    delayed_from = as_of - delayed_window
    delayed_to = as_of - 1.day

    completed_between = lambda do |range|
      sanitize_sql_array(
        ["SUM(CASE WHEN tasks.completed AND tasks.completed_on BETWEEN ? AND ? THEN 1 ELSE 0 END)",
         range.first, range.last]
      )
    end
    open_due_between = lambda do |from, to|
      sanitize_sql_array(
        ["SUM(CASE WHEN tasks.completed THEN 0 WHEN tasks.due_date BETWEEN ? AND ? THEN 1 ELSE 0 END)", from, to]
      )
    end

    open_total = "SUM(CASE WHEN tasks.completed THEN 0 ELSE 1 END)"
    oldest_delayed = sanitize_sql_array(
      ["MIN(CASE WHEN tasks.completed THEN NULL WHEN tasks.due_date BETWEEN ? AND ? THEN tasks.due_date END)",
       delayed_from, delayed_to]
    )
    open_assignees = "COUNT(DISTINCT CASE WHEN tasks.completed THEN NULL ELSE tasks.assigned_to_id END)"

    values = scope.reorder(nil).pick(
      Arel.sql(completed_between.call(this_week)),
      Arel.sql(completed_between.call(last_week)),
      Arel.sql(open_due_between.call(next_week.first, next_week.last)),
      Arel.sql(open_due_between.call(delayed_from, delayed_to)),
      Arel.sql(open_total),
      Arel.sql(oldest_delayed),
      Arel.sql(open_assignees)
    )
    # pick returns nil when the scope has no rows at all
    values ||= []

    {
      completed_this_week: values[0].to_i,
      completed_last_week: values[1].to_i,
      due_next_week: values[2].to_i,
      delayed: values[3].to_i,
      open_total: values[4].to_i,
      # MySQL hands back a Date, SQLite a "YYYY-MM-DD" string.
      oldest_delayed_due_date: values[5].presence&.to_date,
      open_assignees: values[6].to_i
    }
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
