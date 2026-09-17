# Ends an approved obligation (waived / expired / disputed) and removes its
# projections: the recurrence rule and all INCOMPLETE tasks go away, while
# completed tasks and their ObligationFulfillment history are preserved for the
# audit trail (completed occurrences are detached from the rule first, since
# TaskRecurrenceRule#tasks is dependent: :destroy).
class ObligationTeardown < Trailblazer::Operation
  END_STATUSES = %w[waived expired disputed].freeze

  step :validate
  step :teardown_projections
  step :update_status
  left :handle_errors

  def validate(ctx, obligation:, new_status:, **)
    unless END_STATUSES.include?(new_status.to_s)
      ctx[:error] = "Invalid end status '#{new_status}'"
      return false
    end
    return true if obligation.approved?

    ctx[:error] = "Only approved obligations can be #{new_status}"
    false
  end

  def teardown_projections(_ctx, obligation:, **)
    # Incomplete projected tasks (recurring occurrences AND one-time/fired) vanish
    obligation.tasks.incomplete.destroy_all

    if (rule = obligation.task_recurrence_rule)
      # Keep completed occurrences: detach them before the rule cascade-destroys
      rule.tasks.update_all(task_recurrence_rule_id: nil, is_exception: true)
      rule.destroy!
    end
    true
  end

  def update_status(ctx, obligation:, new_status:, **)
    obligation.update!(status: new_status, task_recurrence_rule_id: nil)
  end

  def handle_errors(ctx, **)
    Rails.logger.warn("[ObligationTeardown] #{ctx[:error]}")
    false
  end
end
