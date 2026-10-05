class WorkflowStep < ApplicationRecord
  belongs_to :workflow_template, inverse_of: :workflow_steps

  # Owner reminded when a system/acknowledge step stalls; nil = the record's default owner
  belongs_to :owner_user, class_name: "User", optional: true

  has_many :workflow_step_actors, dependent: :destroy, inverse_of: :workflow_step
  has_many :actor_users, through: :workflow_step_actors, source: :user

  accepts_nested_attributes_for :workflow_step_actors, allow_destroy: true

  # prefix avoids collision with ActiveRecord's built-in .all class method
  enum :quorum_rule,    { any_one: 0, all: 1, majority: 2 }, prefix: :quorum
  enum :on_reject_rule, { stop: 0, previous_step: 1, restart: 2, go_to_step_n: 3 }, prefix: :reject
  # How the step completes: human = approvers vote (today's behaviour), system = a registered data
  # check passes, acknowledge = one person confirms. Existing steps are all human (column default 0).
  enum :kind, { human: 0, system: 1, acknowledge: 2 }, prefix: :kind

  # States a non-human step records when it passes; the first state is always the passing one
  SYSTEM_STATES = "Passed".freeze
  ACKNOWLEDGE_STATES = "Reviewed".freeze
  DEFAULT_HUMAN_STATES = "Approved,Rejected,Needs Info".freeze

  before_validation :default_states_for_kind
  before_validation :assign_next_position

  validates :name,     presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :states,   presence: true
  validates :on_reject_target_step, presence: true, if: -> { reject_go_to_step_n? }
  validate  :actors_must_belong_to_entity
  validate  :check_keys_must_be_registered
  validate  :owner_must_belong_to_entity

  # Virtual attribute — accepts an array of user_ids and reconciles the
  # workflow_step_actors collection. Used by the form's <select multiple>.
  # Creates new actors for newly-selected users, destroys actors for
  # de-selected users, leaves untouched actors alone.
  def actor_user_ids=(ids)
    return if ids.nil?

    selected_ids = Array(ids).map(&:to_i).reject(&:zero?).uniq

    # Look at the in-memory collection (covers both persisted and just-built records).
    current_ids = workflow_step_actors.reject(&:marked_for_destruction?).map(&:user_id).compact

    # Mark for destruction any actor whose user is no longer selected.
    workflow_step_actors.each do |a|
      next if a.user_id.nil?
      a.mark_for_destruction unless selected_ids.include?(a.user_id)
    end

    # Add actors for newly-selected users not already represented.
    (selected_ids - current_ids).each do |uid|
      workflow_step_actors.build(user_id: uid)
    end
  end

  def actor_user_ids
    workflow_step_actors.reject(&:marked_for_destruction?).map(&:user_id).compact
  end

  # The effective reminder interval — nil disables reminders on this step.
  # A step with reminder_interval_days explicitly set (even to 0) overrides the template default.
  # A step with nil inherits from the template (nil template value = reminders disabled globally).
  def effective_reminder_interval
    # _before_type_cast.present? is safe for nil integer columns; .zero? would crash on nil
    return reminder_interval_days if reminder_interval_days_before_type_cast.present?

    workflow_template.reminder_interval_days
  end

  # True for steps the evaluator decides from data or a confirmation (system / acknowledge)
  def evaluated?
    !kind_human?
  end

  # Button labels this step unlocks once passed or not applicable
  def unlock_labels
    unlocks.to_s.split(",").map(&:strip).compact_blank
  end

  # Ordered list of state labels parsed from the CSV field
  def state_list
    states.split(",").map(&:strip).reject(&:blank?)
  end

  private

  # A system/acknowledge step left on the human default states gets its own single passing state,
  # so the existing "first state passes" rule keeps working for it
  # Worked examples E1 (existing steps stay human) — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
  def default_states_for_kind
    return if kind_human?
    return unless states.blank? || states == DEFAULT_HUMAN_STATES

    self.states = kind_system? ? SYSTEM_STATES : ACKNOWLEDGE_STATES
  end

  # Number a step whose position arrived blank. The template form's "Add Step" button clones a
  # row from a WorkflowStep.new template, so its hidden position field is empty — there is no
  # reordering JS on that form to fill one in — and the row would fail the position validations.
  # Siblings are read from the in-memory collection so unsaved rows count too, and nested rows
  # are validated in collection order, so two rows added at once get consecutive numbers.
  def assign_next_position
    return if position.present?

    # Skip self and rows the user just deleted, so a removed last step frees its number
    siblings = workflow_template ? workflow_template.workflow_steps.to_a : []
    taken = siblings.reject { |s| s.equal?(self) || s.marked_for_destruction? }.filter_map(&:position)
    self.position = (taken.max || 0) + 1
  end

  # Check and skip keys must be checks registered for this template's record type, so a Capital Call
  # template can't point at, say, an Investor KYC check (typed keys are never constantized)
  # Worked examples X1, X2 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
  def check_keys_must_be_registered
    type = workflow_template&.workflowable_type
    allowed = WorkflowChecks::Registry.keys_for(type)
    type_label = type.present? ? type.titleize : "general"

    # A system/acknowledge step needs a check; any check given must be registered for the type
    missing_check = check_key.blank? && !kind_human?
    unknown_check = check_key.present? && allowed.exclude?(check_key)
    errors.add(:base, "Check must be a #{type_label} check") if missing_check || unknown_check
    errors.add(:base, "Skip when must be a #{type_label} check") if skip_key.present? && allowed.exclude?(skip_key)
  end

  # The owner must be an employee of the template's organisation
  def owner_must_belong_to_entity
    return if owner_user.nil? || workflow_template.nil?
    return if owner_user.entity_id == workflow_template.entity_id

    errors.add(:owner_user, "must be an employee of this organisation")
  end

  def actors_must_belong_to_entity
    entity_id = workflow_template&.entity_id
    return unless entity_id

    # All actors must be employees of the owning entity
    invalid = workflow_step_actors.reject(&:marked_for_destruction?).any? do |a|
      a.user&.entity_id != entity_id
    end
    errors.add(:base, "All actors must be employees of this organisation") if invalid
  end
end
