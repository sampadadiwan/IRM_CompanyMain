class WorkflowAutoAssignmentRule < ApplicationRecord
  belongs_to :entity
  belongs_to :workflow_template
  belongs_to :created_by, class_name: "User", optional: true

  validates :workflowable_type, presence: true,
                                inclusion: { in: WorkflowTemplate::WORKFLOWABLE_TYPE_OPTIONS }
  validates :priority,          presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate  :template_scoped_to_correct_type
  validate  :conditions_fit_field_list

  # Serialize the text column as a Ruby array of hashes.
  # MySQL does not have native JSON array columns; we use text + manual serialize here.
  serialize :conditions, coder: JSON

  after_initialize :set_conditions_default

  # Whether every condition holds for the given saved workflowable; an empty conditions array always
  # matches (catch-all / default rule). Pass `fields:` when checking several rules for one record so
  # the field list is built once. Design: workflow-rule-condition-builder card 7
  def matches?(workflowable, fields: nil)
    WorkflowRuleMatcher.call(self, workflowable, fields:)
  end

  private

  def set_conditions_default
    self.conditions ||= []
  end

  # Validates that the template's workflowable_type (when set) matches the rule's type.
  def template_scoped_to_correct_type
    return unless workflow_template&.workflowable_type.present?
    return if workflow_template.workflowable_type == workflowable_type
    errors.add(:workflow_template,
               "is scoped to #{workflow_template.workflowable_type} but this rule is for #{workflowable_type}")
  end

  # Every condition must be on this type's field list for this entity, with an operator and value the
  # field allows — otherwise the rule would save and silently never match.
  # Worked examples X1–X5 — openspec/changes/workflow-rule-condition-builder/design.md#worked-examples
  def conditions_fit_field_list
    # The type's own inclusion validation reports an unknown type; nothing to check fields against
    return unless entity && WorkflowTemplate::WORKFLOWABLE_TYPE_OPTIONS.include?(workflowable_type)

    WorkflowRuleFields.for(workflowable_type, entity).errors_for(conditions).each { |message| errors.add(:base, message) }
  end
end
