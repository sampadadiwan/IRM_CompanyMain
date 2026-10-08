# Does an auto-assignment rule match this saved record?
#
# A rule matches when a Ransack search for its conditions, limited to this one record, finds it.
# That reuses what list search already does for amounts (RansackerAmounts: currency units, not cents)
# and custom fields (the json_fields ransackers), instead of a second hand-written comparison engine.
#
# It fails closed, never widening the match:
#   - conditions are re-checked against WorkflowRuleFields first — a custom field or form type can be
#     deleted after the rule was saved;
#   - Ransack drops any condition outside the model's allowlist without an error
#     (ignore_unknown_conditions is on app-wide), which would make the rule match more records than
#     it says, so the number of conditions Ransack applied must equal the number the rule has.
#
# Runs inside the record's save transaction (after_create / after_update), on the same connection,
# so the new row is visible to the query.
# Design: openspec/changes/workflow-rule-condition-builder/design.md#-matcher
class WorkflowRuleMatcher
  # The auth object that unlocks a type's rule-only fields (Workflowable::WorkflowRuleRansack)
  AUTH_OBJECT = :workflow_rule

  def self.call(rule, record, fields: nil)
    new(rule, record, fields).call
  end

  def initialize(rule, record, fields)
    @rule = rule
    @record = record
    @fields = fields || WorkflowRuleFields.for(rule.workflowable_type, rule.entity)
  end

  def call
    conditions = Array(@rule.conditions)
    # No conditions: the catch-all matches every record of its type
    return true if conditions.empty?

    # A condition that is no longer valid skips the rule rather than being searched as-is
    errors = @fields.errors_for(conditions)
    return skip(errors.join("; "), level: :warn) if errors.any?

    search = @record.class.base_class.where(id: @record.id)
                    .ransack(ransack_query(conditions), auth_object: AUTH_OBJECT)

    # Guard against Ransack silently dropping a condition it does not allow
    applied = search.base.conditions.size
    return skip("Ransack applied #{applied} of #{conditions.size} conditions", level: :error) if applied != conditions.size

    search.result.exists?
  rescue StandardError => e
    skip("#{e.class}: #{e.message}", level: :error)
  end

  private

  # Model fields become plain "<attr>_<predicate>" keys; custom fields become "c" groupings on the
  # json ransackers (attribute json_fields / json_field_number, ransacker_args = the field name)
  def ransack_query(conditions)
    conditions.each_with_object({}) do |condition, query|
      field = @fields.field(condition["attribute"])
      predicate = condition["operator"].to_s
      value = ransack_value(predicate, condition["value"])

      if field.custom
        (query["c"] ||= []) << custom_condition(field, predicate, value)
      else
        query["#{field.ransack_name}_#{predicate}"] = value
      end
    end
  end

  # blank / present take a flag rather than a value; in / not_in take a list
  def ransack_value(predicate, value)
    return true if WorkflowRuleFields::NO_VALUE_OPERATORS.include?(predicate)
    return Array.wrap(value).map(&:to_s) if WorkflowRuleFields::LIST_OPERATORS.include?(predicate)

    value.to_s
  end

  # Each list value is its own entry: a single array value would be quoted as one JSON string
  def custom_condition(field, predicate, value)
    values = Array.wrap(value).each_with_index.to_h { |v, i| [i.to_s, { "value" => v }] }
    {
      "a" => { "0" => { "name" => field.ransack_name, "ransacker_args" => field.key.delete_prefix("json_fields.") } },
      "p" => predicate,
      "v" => values
    }
  end

  def skip(reason, level:)
    Rails.logger.public_send(level, "[WorkflowRuleMatcher] Rule #{@rule.id} skipped for #{@record.class.name}##{@record.id}: #{reason}")
    false
  end
end
