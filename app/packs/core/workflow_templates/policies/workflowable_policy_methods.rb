# Policy methods shared by every workflowable type's policy (include it in the policy class).
# Worked examples X6 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
module WorkflowablePolicyMethods
  # The journey panel on its own (reloaded in real time): same access as the record's page
  def journey?
    show?
  end

  # Only a company admin can assign / remove a workflow on a record (its Workflow tab), and only
  # when the entity has workflow templates enabled
  def assign_workflow?
    user.entity&.permissions&.enable_workflow_templates? && user.company_admin? && belongs_to_entity?(user, record)
  end
end
