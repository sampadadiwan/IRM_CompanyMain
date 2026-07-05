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

  # The most recent non-archived instance for this object, or nil if none exists
  # (never launched, or every instance so far has been archived/reset). Memoized —
  # workflow_gated?, workflow_gated_button_labels, and workflow_gate_status_label
  # are all typically called together on the same request-scoped object.
  def current_workflow_instance
    return @current_workflow_instance if defined?(@current_workflow_instance)

    @current_workflow_instance = workflow_instances.where.not(status: :archived).order(created_at: :desc).first
  end

  # True while a workflow is blocking gated actions on this object: opt-in — an object
  # that has never had a workflow launched against it is never gated. Both an in-progress
  # (active) and a failed (rejected) instance keep the gate closed; only a completed
  # instance opens it.
  def workflow_gated?
    instance = current_workflow_instance
    instance.present? && !instance.instance_complete?
  end

  # Button labels (from the current instance's live template, not the frozen snapshot)
  # that should be disabled while workflow_gated? is true. Empty when not gated or when
  # the template sets no labels.
  def workflow_gated_button_labels
    return [] unless workflow_gated?

    current_workflow_instance.workflow_template&.gated_button_labels.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  # "Incomplete" (still active) or "Failed" (rejected) — nil when not gated.
  def workflow_gate_status_label
    instance = current_workflow_instance
    return nil unless instance

    return "Incomplete" if instance.instance_active?
    return "Failed" if instance.instance_rejected?

    nil
  end

  private

  # Called after_create to apply any matching auto-assignment rule.
  # Silently a no-op when no rules exist, already has a template, or the entity
  # does not respond to `entity` (e.g. test stubs without an association).
  def apply_workflow_auto_assignment
    return unless respond_to?(:entity) && entity.present?
    WorkflowAutoAssignmentService.call(workflowable: self)
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
    WorkflowAutoAssignmentService.call(workflowable: self)
  rescue StandardError => e
    Rails.logger.warn("[Workflowable#apply_workflow_auto_assignment_on_update] #{self.class.name}##{id}: #{e.message}")
  end
end
