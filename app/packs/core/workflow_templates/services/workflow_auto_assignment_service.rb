# Evaluates auto-assignment rules for a newly-created workflowable and, when a matching
# rule is found, assigns the template and optionally launches an instance immediately.
class WorkflowAutoAssignmentService
  # @param workflowable [#entity, #class] any Workflowable model instance
  # @param launched_by  [User, nil] user recorded on the launched instance; nil = system
  def self.run(workflowable, launched_by: nil)
    new(workflowable, launched_by: launched_by).run
  end

  def initialize(workflowable, launched_by: nil)
    @workflowable = workflowable
    @launched_by  = launched_by
    @type_name    = workflowable.class.name
  end

  def run
    return if @workflowable.workflow_assignment.present? # already has a template

    rule = matching_rule
    return unless rule

    # Assign the template to the workflowable
    @workflowable.create_workflow_assignment!(
      workflow_template: rule.workflow_template,
      created_by:        rule.created_by
    )

    # Launch immediately when the rule says to
    if rule.auto_launch
      WorkflowInstanceService.launch(@workflowable, launched_by: @launched_by)
    end

    rule
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    # Log and continue — auto-assignment is best-effort, never a hard failure
    Rails.logger.warn("[WorkflowAutoAssignmentService] Rule skipped for #{@type_name}##{@workflowable.id}: #{e.message}")
    nil
  end

  private

  # Returns the highest-priority (lowest priority integer) rule whose conditions match.
  def matching_rule
    WorkflowAutoAssignmentRule
      .where(entity: @workflowable.entity, workflowable_type: @type_name)
      .order(:priority)
      .includes(:workflow_template)
      .find { |rule| rule.matches?(@workflowable) }
  end
end
