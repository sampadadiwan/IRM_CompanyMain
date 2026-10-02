class WorkflowAutoAssignmentRule < ApplicationRecord
  belongs_to :entity
  belongs_to :workflow_template
  belongs_to :created_by, class_name: "User", optional: true

  # Supported operators for condition matching.
  # DB columns only are allowed as attribute names to prevent arbitrary method calls.
  OPERATORS = %w[eq not_eq gt lt gte lte in not_in present blank].freeze

  # Form type names of KYCs, for the rule form's "KYC form type" picker (investor-kyc-journey E27)
  KYC_FORM_TYPE_NAMES = %w[IndividualKyc NonIndividualKyc InvestorKyc].freeze

  # The form type a KYC rule picks (its form_type_id eq condition), or nil
  def kyc_form_type_id
    Array(conditions).find { |c| c.is_a?(Hash) && c["attribute"].to_s == "form_type_id" && c["operator"] == "eq" }&.dig("value")
  end

  validates :workflowable_type, presence: true,
                                inclusion: { in: WorkflowTemplate::WORKFLOWABLE_TYPE_OPTIONS }
  validates :priority,          presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate  :template_scoped_to_correct_type
  validate  :conditions_are_valid_json_array

  # Serialize the text column as a Ruby array of hashes.
  # MySQL does not have native JSON array columns; we use text + manual serialize here.
  serialize :conditions, coder: JSON

  after_initialize :set_conditions_default

  # Evaluate all conditions against the given workflowable object.
  # Returns true only if every condition in the array matches.
  # An empty conditions array always returns true (catch-all / default rule).
  def matches?(workflowable)
    Array(conditions).all? { |cond| evaluate_condition(workflowable, cond) }
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

  def conditions_are_valid_json_array
    return if Array(conditions).all? { |c| c.is_a?(Hash) && c["attribute"].present? && OPERATORS.include?(c["operator"]) }
    errors.add(:conditions, "must be an array of {attribute, operator, value} hashes with a valid operator")
  end

  # Evaluate a single condition hash against the workflowable.
  # Only reads DB column values — never calls arbitrary methods to prevent injection.
  def evaluate_condition(workflowable, cond)
    attribute = cond["attribute"].to_s
    operator  = cond["operator"].to_s
    expected  = cond["value"]

    # Guard: only allow DB columns so arbitrary method dispatch is impossible
    unless workflowable.class.column_names.include?(attribute)
      Rails.logger.warn("[WorkflowAutoAssignmentRule] Skipped unknown attribute '#{attribute}' on #{workflowable.class.name}")
      return false
    end

    actual = workflowable.read_attribute(attribute)

    case operator
    when "eq"      then actual.to_s  == expected.to_s
    when "not_eq"  then actual.to_s  != expected.to_s
    when "gt"      then actual.to_d  >  expected.to_d
    when "lt"      then actual.to_d  <  expected.to_d
    when "gte"     then actual.to_d  >= expected.to_d
    when "lte"     then actual.to_d  <= expected.to_d
    when "in"      then Array(expected).map(&:to_s).include?(actual.to_s)
    when "not_in"  then !Array(expected).map(&:to_s).include?(actual.to_s)
    when "present" then actual.present?
    when "blank"   then actual.blank?
    else false
    end
  rescue StandardError => e
    Rails.logger.error("[WorkflowAutoAssignmentRule] Condition evaluation error: #{e.message}")
    false
  end
end
