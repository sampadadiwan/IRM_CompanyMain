class WorkflowInstancePolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      # entity_id is denormalised onto WorkflowInstance so no join is needed
      scope.where(entity_id: user.entity_id)
    end
  end

  # Any entity employee may browse their entity's workflow instances
  def index?
    workflow_templates_enabled?
  end

  # Any entity employee may view an instance for an object in their entity
  def show?
    workflow_templates_enabled? && belongs_to_entity?(user, record)
  end

  # Only company_admin can launch a new instance
  def create?
    workflow_templates_enabled? && user.company_admin? && belongs_to_entity?(user, record)
  end

  # Admin-only: manually push a step to a specific resolved state (tiebreaker / override)
  def advance?
    workflow_templates_enabled? && user.company_admin? && belongs_to_entity?(user, record)
  end

  # Admin-only: reset instance to step 1
  def reset?
    advance?
  end

  # Admin-only: archive a stalled instance (unblocks assignment removal)
  def archive?
    advance?
  end

  # Admin-only: send manual reminder to pending actors on the current step
  def send_reminder?
    advance?
  end

  # Any entity employee with view access can export the audit trail CSV
  def export_audit_trail?
    workflow_templates_enabled? && belongs_to_entity?(user, record)
  end

  private

  def workflow_templates_enabled?
    user.entity&.permissions&.enable_workflow_templates?
  end
end
