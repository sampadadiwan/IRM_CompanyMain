# The custom form editor (form_types/_form): a list of fields on the left and one field's settings on the right.
# Only the screen changed — every input keeps the name and id the old stacked form used, so FormTypesController#update
# and form_type_params receive exactly what they always did. These helpers supply the plain-language labels and the
# option lists the editor's dropdowns and pickers need.
module FormTypeEditorHelper
  # Field types offered in the Type dropdown, value => friendly label. The values are what is stored; only the
  # labels are new. Calculation stays support-only, as before.
  FCF_TYPE_LABELS = {
    "TextField" => "Text",
    "TextArea" => "Long text",
    "NumberField" => "Number",
    "Money" => "Money",
    "DateField" => "Date",
    "Select" => "Dropdown",
    "DataList" => "Dropdown with typing",
    "Radio" => "Radio buttons",
    "MultiSelect" => "Multi select",
    "CheckBox" => "Check box",
    "File" => "File upload",
    "Header" => "Section heading",
    "GridColumns" => "Grid columns",
    "Calculation" => "Calculation"
  }.freeze

  # Condition criteria, stored value => the words used in the "Only when [field] [is] [value]" sentence
  FCF_CRITERIA_LABELS = {
    "eq" => "is", "not_eq" => "is not", "contains" => "contains",
    "lt" => "is less than", "lte" => "is at most", "gt" => "is more than", "gte" => "is at least"
  }.freeze

  # [label, value] pairs for the Type dropdown. An older type with no current name (fcf_type_value) is kept as its own
  # option, so saving never silently turns it into whichever option happens to come first.
  def fcf_type_options(field)
    types = FCF_TYPE_LABELS.keys
    types -= ["Calculation"] unless current_user.support? || Rails.env.local?
    options = types.map { |type| [FCF_TYPE_LABELS[type], type] }
    current = fcf_type_value(field)
    options.unshift(["#{current} (older type)", current]) if current.present? && types.exclude?(current)
    options
  end

  # The type the dropdown starts on. Older fields store a few types under their former name ("text_field"); those are
  # shown as the current type they mean ("TextField"), because the model only accepts current names and any save of
  # the form re-validates every field. A type with no current name is left as it is.
  def fcf_type_value(field)
    current = field.field_type.to_s
    return current if current.blank? || FCF_TYPE_LABELS.key?(current)

    FCF_TYPE_LABELS.key?(current.camelize) ? current.camelize : current
  end

  # [label, value] pairs for the condition's criteria dropdown
  def fcf_criteria_options
    FCF_CRITERIA_LABELS.map { |value, label| [label, value] }
  end

  def fcf_type_label(field_type)
    FCF_TYPE_LABELS.fetch(field_type.to_s, field_type.to_s)
  end

  # The heading each wizard step gets in the list and in the Step dropdown, by enum key. Steps 4–9 carry the form's
  # own step labels when set ("Step 4 · Bank details"); "end" is the default step every field starts on.
  def fcf_step_labels(form_type)
    FormCustomField.steps.keys.index_with do |key|
      number = FormCustomField.steps[key]
      case key
      when "end" then "Step 3 (Default)"
      when "one", "two", "three" then "Step #{number}"
      else
        custom = form_type.step_labels.presence&.fetch(number.to_s, nil)
        custom.present? ? "Step #{number} · #{custom}" : "Step #{number} (Extra)"
      end
    end
  end

  # [label, key] pairs for the Step dropdown, in the order the list shows the steps (the stored step number)
  def fcf_step_options(form_type)
    labels = fcf_step_labels(form_type)
    FormCustomField.steps.sort_by { |_key, number| number }.map { |key, _number| [labels[key], key] }
  end

  # The fields a condition may depend on: the standard fields FormCustomField#condition_on_custom_field accepts for
  # this record type, then the form's own custom fields. Memoised per request — the partial renders once per field.
  def fcf_condition_fields(form_type)
    @fcf_condition_fields ||= {}.compare_by_identity
    @fcf_condition_fields[form_type] ||= begin
      custom = form_type.form_custom_fields.reject(&:marked_for_destruction?).filter_map do |fcf|
        [fcf.human_label, fcf.name] if fcf.name.present?
      end
      fcf_standard_condition_fields(form_type) + custom
    end
  end

  # The standard (non custom) fields a condition may use — only these two, per FormCustomField#condition_on_custom_field
  def fcf_standard_condition_fields(form_type)
    { "Investor" => [["Category (standard field)", "category"]],
      "InvestorKyc" => [["KYC type (standard field)", "kyc_type"]] }.fetch(form_type.name.to_s, [])
  end

  # [label, value] pairs for one field's "Only when" dropdown: blank (always), the candidates except itself, and
  # its current value even when it matches nothing — shown as typed so opening and saving the form loses nothing.
  def fcf_condition_options(form_type, field)
    options = fcf_condition_fields(form_type).reject { |_label, name| name == field.name }
    current = field.condition_on
    options += [["#{current} (not a field on this form)", current]] if current.present? && options.none? { |_l, n| n == current }
    [["— always —", ""]] + options
  end

  # The firm's users for the "Visible to" picker, as [id, "Name (email)"]. One query; the picker is built in the
  # browser from this list so it is not repeated inside every field's pane.
  def fcf_user_options(form_type)
    User.where(entity_id: form_type.entity_id).order(:first_name, :last_name)
        .pluck(:id, :first_name, :last_name, :email)
        .map do |id, first, last, email|
          # A user with no name on file is shown by email alone
          name = "#{first} #{last}".squish
          [id, name.present? ? "#{name} (#{email})" : email]
        end
  end
end
