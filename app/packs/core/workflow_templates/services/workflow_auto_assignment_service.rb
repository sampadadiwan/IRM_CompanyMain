# Evaluates auto-assignment rules for a newly-created workflowable and, when a matching
# rule is found, assigns the template and optionally launches an instance immediately.
#
# This is where a capital call's or distribution's journey gets attached: JourneySetup's rules are
# created with auto_launch: true, so a matching rule here both assigns the template and launches the
# evaluated instance the step bar is drawn from. A disabled template therefore means no journey at
# all on new records — nothing to render, nothing to remind about.
class WorkflowAutoAssignmentService < Trailblazer::Operation
  step :check_not_already_assigned, Output(:failure) => End(:already_assigned)
  step :find_matching_rule,          Output(:failure) => End(:no_matching_rule)
  step :check_template_enabled,      Output(:failure) => End(:template_disabled)
  step :assign_template,             Output(:failure) => End(:assignment_failed)
  step :launch_if_auto_launch

  def check_not_already_assigned(_ctx, workflowable:, **)
    workflowable.workflow_assignment.blank? # already has a template — nothing to do
  end

  # Returns the highest-priority (lowest priority integer) rule whose conditions match.
  def find_matching_rule(ctx, workflowable:, **)
    ctx[:rule] = WorkflowAutoAssignmentRule
      .where(entity: workflowable.entity, workflowable_type: workflowable.workflowable_type_name)
      .order(:priority)
      .includes(:workflow_template)
      .find { |rule| rule.matches?(workflowable) }
    ctx[:rule].present?
  end

  # Stop here when the winning rule points at a disabled template: the record gets no template and
  # no journey.
  #
  # Deliberately checked AFTER the match rather than filtering disabled templates out of the query:
  # filtering would let the next-priority rule take over, so disabling the Light journey would
  # silently move imported capital calls onto the Full one. "Disabled" means not used, not
  # "substitute a different workflow" — the rule that matched is the rule that applies, and if its
  # template is off, nothing is assigned.
  def check_template_enabled(ctx, workflowable:, **)
    return true if ctx[:rule].workflow_template&.enabled?

    Rails.logger.info(
      "[WorkflowAutoAssignmentService] Rule #{ctx[:rule].id} skipped for " \
      "#{workflowable.class.name}##{workflowable.id}: template \"#{ctx[:rule].workflow_template}\" is disabled"
    )
    false
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
