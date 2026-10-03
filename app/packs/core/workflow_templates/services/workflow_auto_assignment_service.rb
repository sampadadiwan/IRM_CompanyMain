# Evaluates auto-assignment rules for a newly-created workflowable and, when a matching
# rule is found, assigns the template and optionally launches an instance immediately.
#
# This is where a capital call's or distribution's journey gets attached: JourneySetup's rules are
# created with auto_launch: true, so a matching rule here both assigns the template and launches the
# evaluated instance the step bar is drawn from.
#
# A disabled template's rules are dormant, not blocking: the walk skips them and carries on down the
# chain, so a retired template cannot deny a record the workflow a live rule would have given it.
# The rules are never touched — they resume their place the moment the template is enabled again.
# A record gets no workflow only when no live template's rule matches it.
class WorkflowAutoAssignmentService < Trailblazer::Operation
  step :check_not_already_assigned, Output(:failure) => End(:already_assigned)
  step :find_matching_rule,          Output(:failure) => End(:no_matching_rule)
  step :assign_template,             Output(:failure) => End(:assignment_failed)
  step :launch_if_auto_launch

  def check_not_already_assigned(_ctx, workflowable:, **)
    workflowable.workflow_assignment.blank? # already has a template — nothing to do
  end

  # Returns the highest-priority (lowest priority integer) live rule whose conditions match.
  #
  # "Live" is part of the match, not a test applied afterwards: a rule exists to hand over one
  # template (belongs_to :workflow_template), so when that template is disabled the rule has nothing
  # to give and stands aside rather than consuming the record. Checking it after the match instead
  # would let one catch-all rule on a retired template deny every record of the type a workflow,
  # with no later rule — at any priority, on any live template — ever reachable.
  #
  # Ordered by (priority, id): priority decides precedence, and id breaks a tie by creation order so
  # two rules sharing a priority resolve the same way on every run. Ordering by priority alone left
  # the winner to whatever the database happened to return.
  #
  # workflow_template may be nil for a rule whose template row was deleted straight in the database;
  # such a rule is skipped like any dormant one rather than raising into record creation.
  def find_matching_rule(ctx, workflowable:, **)
    # One field list for the whole walk: each rule's match re-checks its conditions against it
    fields = WorkflowRuleFields.for(workflowable.workflowable_type_name, workflowable.entity)
    ctx[:rule] = WorkflowAutoAssignmentRule
      .where(entity: workflowable.entity, workflowable_type: workflowable.workflowable_type_name)
      .order(:priority, :id)
      .includes(:workflow_template)
      .find { |rule| rule.workflow_template&.enabled? && rule.matches?(workflowable, fields:) }
    ctx[:rule].present?
  end

  def assign_template(ctx, workflowable:, **)
    workflowable.create_workflow_assignment!(
      workflow_template: ctx[:rule].workflow_template,
      created_by:        ctx[:rule].created_by
    )
    true
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    # Log and continue — auto-assignment is best-effort, never a hard failure
    Rails.logger.warn("[WorkflowAutoAssignmentService] Rule skipped for #{workflowable.class.name}##{workflowable.id}: #{e.message}")
    false
  end

  def launch_if_auto_launch(ctx, workflowable:, launched_by: nil, **)
    return true unless ctx[:rule].auto_launch

    result = WorkflowInstanceLaunch.call(workflowable: workflowable, launched_by: launched_by)
    unless result.success?
      Rails.logger.warn("[WorkflowAutoAssignmentService] Auto-launch failed for #{workflowable.class.name}##{workflowable.id}: #{result[:errors]}")
    end
    true
  end
end
