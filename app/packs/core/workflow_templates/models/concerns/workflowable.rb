module Workflowable
  extend ActiveSupport::Concern

  included do
    has_one  :workflow_assignment, as: :workflowable, dependent: :destroy
    has_many :workflow_instances,  as: :workflowable, dependent: :destroy

    # After every new record is persisted, check whether any auto-assignment rule matches.
    # Runs in an after_create so the object has a real id before rules are evaluated.
    after_create :apply_workflow_auto_assignment

    # Re-evaluate rules when any tracked attribute changes on an existing record.
    # Only fires the service when the object doesn't already have a template assigned,
    # preventing repeated re-assignment after the first match.
    after_update :apply_workflow_auto_assignment_on_update
  end

  # The template currently assigned to this object, resolved through WorkflowAssignment.
  def workflow_template
    workflow_assignment&.workflow_template
  end

  # Human-readable name shown in emails and the instance page.
  # Defaults to to_s — override only if the model's to_s is not user-friendly.
  def workflow_display_name
    to_s
  end

  # URL to the object shown in emails and the instance page.
  # Defaults to the conventional Rails path helper derived from the class name
  # (e.g. InvestorKyc → investor_kyc_path(self), CapitalCommitment → capital_commitment_path(self)).
  # Override only for models with non-standard routes (e.g. STI subclasses, scoped routes).
  def workflow_url(routes = Rails.application.routes.url_helpers)
    helper = :"#{self.class.name.underscore}_path"
    routes.public_send(helper, self)
  rescue NoMethodError
    raise NotImplementedError,
          "#{self.class.name} has no standard route helper '#{self.class.name.underscore}_path'. " \
          "Implement #workflow_url explicitly."
  end

  # Files to attach to step-activation emails when attach_document_in_email is true.
  # Returns [] by default — override in models that have associated files.
  def workflow_attachable_files
    []
  end

  private

  # Called after_create to apply any matching auto-assignment rule.
  # Silently a no-op when no rules exist, already has a template, or the entity
  # does not respond to `entity` (e.g. test stubs without an association).
  def apply_workflow_auto_assignment
    return unless respond_to?(:entity) && entity.present?
    WorkflowAutoAssignmentService.run(self)
  rescue StandardError => e
    Rails.logger.warn("[Workflowable#apply_workflow_auto_assignment] #{self.class.name}##{id}: #{e.message}")
  end

  # Called after_update to re-evaluate rules when the record changes.
  # Guards: skip if no rules could possibly match (no rules for this type+entity),
  # or if a template is already assigned (nothing left to auto-assign).
  def apply_workflow_auto_assignment_on_update
    return unless respond_to?(:entity) && entity.present?
    return if workflow_assignment.present?
    return unless WorkflowAutoAssignmentRule.where(entity: entity, workflowable_type: self.class.name).exists?
    WorkflowAutoAssignmentService.run(self)
  rescue StandardError => e
    Rails.logger.warn("[Workflowable#apply_workflow_auto_assignment_on_update] #{self.class.name}##{id}: #{e.message}")
  end
end
