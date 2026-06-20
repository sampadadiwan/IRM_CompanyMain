class WorkflowStep < ApplicationRecord
  belongs_to :workflow_template, inverse_of: :workflow_steps

  has_many :workflow_step_actors, dependent: :destroy, inverse_of: :workflow_step
  has_many :actor_users, through: :workflow_step_actors, source: :user

  accepts_nested_attributes_for :workflow_step_actors, allow_destroy: true

  # prefix avoids collision with ActiveRecord's built-in .all class method
  enum :quorum_rule,    { any_one: 0, all: 1, majority: 2 }, prefix: :quorum
  enum :on_reject_rule, { stop: 0, previous_step: 1, restart: 2, go_to_step_n: 3 }, prefix: :reject

  validates :name,     presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :states,   presence: true
  validates :on_reject_target_step, presence: true, if: -> { reject_go_to_step_n? }
  validate  :actors_must_belong_to_entity

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

  # Ordered list of state labels parsed from the CSV field
  def state_list
    states.split(",").map(&:strip).reject(&:blank?)
  end

  private

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
