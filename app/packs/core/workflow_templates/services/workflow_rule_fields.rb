# The fields an auto-assignment rule may test for one record type and one entity, with each field's
# kind, operators and allowed values.
#
# This is the single list behind the rule form's dropdowns (to_builder_json), the save-time checks
# (errors_for, via WorkflowAutoAssignmentRule), the matcher's re-check (WorkflowRuleMatcher) and the
# words on the template page's rules table (describe). Keeping all four on one list is what stops the
# form offering something the server refuses, or a rule silently matching nothing.
#
# Fields come from:
#   - the model's Ransack allowlist for rules: ransackable_attributes(:workflow_rule), i.e. what list
#     search exposes plus the type's declared rule-only extras (Workflowable.workflow_rule_fields);
#   - the custom fields on this entity's forms for the type (keys "json_fields.<name>").
#
# Stored operators are Ransack predicate names, so a condition translates 1:1 into a search.
# Design: openspec/changes/workflow-rule-condition-builder/design.md#-field-list
class WorkflowRuleFields
  Field = Struct.new(:key, :label, :kind, :group, :operators, :custom, :ransack_name, :options_loader, keyword_init: true) do
    # Allowed values for reference and option fields, as [[value, label], ...]; loaded on first use
    def options
      @options ||= options_loader ? options_loader.call : []
    end

    def option_label(value)
      options.find { |v, _| v.to_s == value.to_s }&.last
    end
  end

  # Operator words, shared by the form and the rules table
  OPERATOR_LABELS = {
    "eq" => "is", "not_eq" => "is not", "cont" => "contains",
    "in" => "is one of", "not_in" => "is not one of",
    "gt" => "greater than", "gteq" => "at least", "lt" => "less than", "lteq" => "at most",
    "blank" => "is blank", "present" => "is present"
  }.freeze

  # Operators per kind (design card ③). MultiSelect custom fields store several values, so they
  # support "contains" rather than "is". Custom option fields can also be left unanswered, hence
  # blank / present.
  OPERATORS_BY_KIND = {
    "text" => %w[eq not_eq cont in blank present],
    "number" => %w[eq not_eq gt gteq lt lteq],
    "date" => %w[eq not_eq gt gteq lt lteq],
    "boolean" => %w[eq],
    "reference" => %w[eq not_eq in not_in],
    "option" => %w[eq not_eq in not_in blank present],
    "multi_option" => %w[cont blank present]
  }.freeze

  # Operators that take no value, and those that take a list
  NO_VALUE_OPERATORS = %w[blank present].freeze
  LIST_OPERATORS = %w[in not_in].freeze

  # Model columns offered as entity-scoped dropdowns; every other *_id is left out (unbounded lists)
  REFERENCE_FIELDS = %w[form_type_id fund_id].freeze

  # Labels where the column name reads badly
  LABELS = { "form_type_id" => "Form type", "fund_id" => "Fund", "manual_generation" => "Imported" }.freeze

  # Ransack plumbing for custom fields, never offered as fields themselves
  RANSACK_PLUMBING = Workflowable::WorkflowRuleRansack::JSON_RANSACKERS

  # Custom field types a rule cannot test: no stored value (Header, GridColumns), attachments (File),
  # recomputed after save (Calculation), or an inconsistent stored shape (CheckBox)
  EXCLUDED_CUSTOM_TYPES = %w[File Header GridColumns Calculation CheckBox].freeze

  # Custom field type → kind
  CUSTOM_KINDS = {
    "TextField" => "text", "TextArea" => "text",
    "NumberField" => "number", "Money" => "number",
    "DateField" => "date",
    "Select" => "option", "Radio" => "option", "DataList" => "option",
    "MultiSelect" => "multi_option"
  }.freeze

  INVALID_SHAPE = "The JSON is not a valid list of conditions.".freeze

  attr_reader :workflowable_type, :entity, :model

  def self.for(workflowable_type, entity)
    new(workflowable_type, entity)
  end

  def initialize(workflowable_type, entity)
    raise ArgumentError, "Unknown workflowable type #{workflowable_type.inspect}" unless WorkflowTemplate::WORKFLOWABLE_TYPE_OPTIONS.include?(workflowable_type.to_s)

    @workflowable_type = workflowable_type.to_s
    @entity = entity
    @model = @workflowable_type.constantize
  end

  # Model fields first, then custom fields; each group sorted by label
  def fields
    @fields ||= (model_fields.sort_by(&:label) + custom_fields.sort_by(&:label))
  end

  def field(key)
    fields_by_key[key.to_s]
  end

  # Messages for every invalid condition ("Condition N: …"), or the shape message alone when the
  # input is not a list of {attribute, operator, value} hashes. [] means valid.
  def errors_for(conditions)
    return [INVALID_SHAPE] unless valid_shape?(conditions)

    conditions.each_with_index.filter_map do |condition, index|
      problem = condition_problem(condition)
      "Condition #{index + 1}: #{problem}" if problem
    end
  end

  # "Form type is Individual — Fund IV", in the words the rule form uses
  def describe(condition)
    key = condition["attribute"].to_s
    field = field(key)
    return "Unknown field: #{display_key(key)}" unless field

    operator = condition["operator"].to_s
    words = [field.label, OPERATOR_LABELS.fetch(operator, operator)]
    words << describe_value(field, condition["value"]) unless NO_VALUE_OPERATORS.include?(operator)
    words.join(" ")
  end

  # How the record type reads in the form and the field group heading ("KYC", "Capital Call")
  def type_label
    workflowable_type == "InvestorKyc" ? "KYC" : workflowable_type.titleize
  end

  # Everything the rule form's Stimulus controller needs to draw rows
  def to_builder_json
    {
      fields: fields.map do |f|
        {
          key: f.key, label: f.label, kind: f.kind, group: f.group,
          operators: f.operators.map { |op| { value: op, label: OPERATOR_LABELS[op] } },
          options: f.options.map { |value, label| { value: value.to_s, label: label } }
        }
      end,
      no_value_operators: NO_VALUE_OPERATORS,
      list_operators: LIST_OPERATORS
    }
  end

  private

  def fields_by_key
    @fields_by_key ||= fields.index_by(&:key)
  end

  # --- building the list ---

  # The model's searchable fields plus its rule-only extras, minus excluded ones and Ransack plumbing.
  # Also minus the list filters' custom-field names (WithCustomField.register_cf_ransackers), which
  # the allowlist adds for the signed-in company: custom fields come from this company's forms below,
  # with their real kinds, never as plain search fields.
  def model_fields
    names = model.ransackable_attributes(:workflow_rule) - RANSACK_PLUMBING - model.workflow_rule_excluded
    names -= model.cf_filter_names if model.include?(WithCustomField)
    names.filter_map do |name|
      kind = model_field_kind(name)
      next unless kind

      Field.new(key: name, label: model_field_label(name), kind: kind, group: "#{type_label} fields",
                operators: OPERATORS_BY_KIND.fetch(kind), custom: false, ransack_name: name,
                options_loader: reference_options_loader(name))
    end
  end

  # nil leaves the field out (unbounded references, unknown shapes)
  def model_field_kind(name)
    return "reference" if REFERENCE_FIELDS.include?(name)
    return nil if name.end_with?("_id")

    ransacker = model._ransackers[name]
    return ransacker_kind(name, ransacker) if ransacker

    column = model.columns_hash[name]
    column ? kind_for_type(column.type) : nil
  end

  # RansackerAmounts ransackers have no declared type; their *_cents column marks them as amounts
  def ransacker_kind(name, ransacker)
    return "number" if model.columns_hash.key?("#{name}_cents")

    kind_for_type(ransacker.type)
  end

  def kind_for_type(type)
    case type&.to_sym
    when :string, :text then "text"
    when :integer, :decimal, :float, :bigint then "number"
    when :date, :datetime then "date"
    when :boolean then "boolean"
    end
  end

  def model_field_label(name)
    LABELS[name] || model.human_attribute_name(name)
  end

  # Entity-scoped option lists for the two reference fields
  def reference_options_loader(name)
    case name
    when "form_type_id"
      -> { entity_form_types.map { |ft| [ft.id, form_type_label(ft)] } }
    when "fund_id"
      -> { entity.funds.order(:name).pluck(:id, :name) }
    end
  end

  # One custom field per name across the type's forms; the first form (by id) defines label and kind
  def custom_fields
    return [] unless model.include?(WithCustomField)

    entity_form_types.flat_map(&:form_custom_fields)
                     .reject { |fcf| EXCLUDED_CUSTOM_TYPES.include?(fcf.field_type) || fcf.name.blank? }
                     .uniq(&:name)
                     .filter_map { |fcf| custom_field(fcf) }
  end

  def custom_field(fcf)
    kind = CUSTOM_KINDS[fcf.field_type]
    return unless kind

    options = fcf.options.compact_blank
    Field.new(key: "json_fields.#{fcf.name}", label: fcf.human_label, kind: kind, group: "Custom fields",
              operators: OPERATORS_BY_KIND.fetch(kind), custom: true,
              ransack_name: kind == "number" ? "json_field_number" : "json_fields",
              options_loader: %w[option multi_option].include?(kind) ? -> { options.map { |o| [o, o] } } : nil)
  end

  # This entity's forms for the type (KYCs: all three STI names), with their fields preloaded
  def entity_form_types
    @entity_form_types ||= entity.form_types.where(name: model.workflow_rule_form_type_names)
                                 .includes(:form_custom_fields).order(:name, :tag, :id).to_a
  end

  # "Individual — Fund IV"; the generic KYC form reads "Any type"
  def form_type_label(form_type)
    base = form_type.name == "InvestorKyc" ? "Any type" : form_type.name.delete_suffix("Kyc").titleize
    "#{base} — #{form_type.tag}"
  end

  # --- validating ---

  def valid_shape?(conditions)
    conditions.is_a?(Array) && conditions.all? { |c| c.is_a?(Hash) && c["attribute"].present? && c["operator"].present? }
  end

  # The first problem with one condition, or nil
  def condition_problem(condition)
    key = condition["attribute"].to_s
    field = field(key)
    return "Unknown field \"#{display_key(key)}\"." unless field

    operator = condition["operator"].to_s
    return "\"#{OPERATOR_LABELS.fetch(operator, operator)}\" can't be used with #{field.label}." unless field.operators.include?(operator)
    return nil if NO_VALUE_OPERATORS.include?(operator)

    values = Array.wrap(condition["value"]).map { |v| v.to_s.strip }
    return "#{field.label} needs a value." if values.empty? || values.any?(&:blank?)
    return "#{field.label} takes one value with \"#{OPERATOR_LABELS[operator]}\"." if values.size > 1 && LIST_OPERATORS.exclude?(operator)

    value_problem(field, values)
  end

  def value_problem(field, values)
    case field.kind
    when "number"
      "#{field.label} needs a number." unless values.all? { |v| number?(v) }
    when "date"
      "#{field.label} needs a date." unless values.all? { |v| date?(v) }
    when "boolean"
      "#{field.label} needs Yes or No." unless values.all? { |v| %w[true false].include?(v) }
    when "reference"
      unknown = values.reject { |v| field.option_label(v) }
      "#{field.label} #{unknown.join(', ')} is not one of this company's #{field.label.downcase.pluralize}." if unknown.any?
    when "option", "multi_option"
      unknown = values.reject { |v| field.option_label(v) }
      "\"#{unknown.join(', ')}\" is not an option of #{field.label}." if unknown.any?
    end
  end

  def number?(value)
    BigDecimal(value)
    true
  rescue ArgumentError
    false
  end

  def date?(value)
    Date.iso8601(value)
    true
  rescue Date::Error
    false
  end

  # --- describing ---

  def describe_value(field, value)
    Array.wrap(value).map { |v| value_label(field, v.to_s) }.join(", ")
  end

  def value_label(field, value)
    case field.kind
    when "reference", "option", "multi_option" then field.option_label(value) || value
    when "boolean" then value == "true" ? "Yes" : "No"
    when "date" then date?(value) ? I18n.l(Date.iso8601(value)) : value
    else value
    end
  end

  # Custom-field keys are shown by their field name, as the admin typed them
  def display_key(key)
    key.delete_prefix("json_fields.")
  end
end
