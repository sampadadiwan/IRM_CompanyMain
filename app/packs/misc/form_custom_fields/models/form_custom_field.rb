class FormCustomField < ApplicationRecord
  HIDDEN_FIELDS = %w[Calculation GridColumns].freeze

  VALID_FIELD_TYPES = %w[TextField NumberField DateField TextArea CheckBox Radio Select
                         DataList MultiSelect Money File Header GridColumns Calculation].freeze
  OPTION_FIELD_TYPES = %w[Select Radio DataList MultiSelect].freeze
  VALID_CONDITION_CRITERIAS = %w[eq not_eq contains lt lte gt gte].freeze
  VALID_CONDITION_STATES = %w[show].freeze
  VALID_FORMATS = %w[email phone url alphanumeric pan gstin ifsc].freeze

  FORMAT_PATTERNS = {
    "email" => /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/i,
    "phone" => /\A[\d\s+\-()\[\]]{7,20}\z/,
    "url" => %r{\Ahttps?://.+}i,
    "alphanumeric" => /\A[a-zA-Z0-9]+\z/,
    "pan" => /\A[A-Z]{5}[0-9]{4}[A-Z]\z/,
    "gstin" => /\A[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]\z/,
    "ifsc" => /\A[A-Z]{4}0[A-Z0-9]{6}\z/
  }.freeze

  REGULATORY_ENVS = %w[SEBI CRISIL IFSC MAS].freeze
  REGULATORY_FIELD_MODELS = %w[IndividualKyc NonIndividualKyc InvestmentInstrument].freeze

  VALIDATION_RULE_KEYS = %w[min_length max_length min_value max_value min_date max_date
                            min_selections max_selections pattern format unique
                            error_message max_size_mb].freeze

  VALIDATION_RULE_KEYS.each do |key|
    define_method("vr_#{key}") { (validation_rules || {})[key] }
    define_method("vr_#{key}=") do |val|
      self.validation_rules ||= {}
      if key == "unique"
        ["1", true, "true"].include?(val) ? validation_rules[key] = true : validation_rules.delete(key)
      else
        cleaned = val.to_s.strip.presence
        cleaned ? validation_rules[key] = cleaned : validation_rules.delete(key)
      end
    end
  end

  belongs_to :form_type
  acts_as_list scope: :form_type

  # Values 4–9 are extra dynamic steps used in multi-step forms (e.g. investor_kyc).
  # Values 1–3 map to the fixed infra steps; 100 (end) is the default "append to last fixed step".
  enum :step,  { one: 1, two: 2, three: 3, end: 100, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9 }

  EXTRA_STEP_RANGE = (4..9)

  validates :name, :show_user_ids, length: { maximum: 100 }
  validates :label, length: { maximum: 254 }
  validates :name, uniqueness: { scope: :form_type_id }
  validates :name, presence: true
  normalizes :name, :label, with: ->(value) { value&.strip }
  # condition_params is compared against a stored value, so padding around it is never
  # meaningful — it only ever causes a condition to silently stop matching.
  normalizes :condition_params, with: ->(value) { value&.strip }

  validates :field_type, inclusion: { in: VALID_FIELD_TYPES }
  validates :condition_criteria, inclusion: { in: VALID_CONDITION_CRITERIAS }, allow_blank: true
  validates :condition_state, inclusion: { in: VALID_CONDITION_STATES }, allow_blank: true
  validates :reg_env, inclusion: { in: REGULATORY_ENVS }, allow_blank: true

  has_rich_text :info

  RENDERERS = { Money: "/form_custom_fields/display/money", DateField: "/form_custom_fields/display/date", MultiSelect: "/form_custom_fields/display/multi_select", CheckBox: "/form_custom_fields/display/check_box", NumberField: "/form_custom_fields/display/number", TextArea: "/form_custom_fields/display/text_area" }.freeze

  # NumberField meta_data holds "precision,separator", e.g. "2,comma" or "0,none".
  # Blank meta_data means no formatting is applied (raw value is displayed).
  NUMBER_FORMAT_DELIMITERS = { "comma" => ",", "none" => "" }.freeze

  def number_format
    return nil unless field_type == "NumberField" && meta_data.present?

    precision_part, separator_part = meta_data.split(",", 2).map { |s| s.to_s.strip }
    precision = Integer(precision_part, exception: false)
    return nil if precision.nil? || precision.negative?

    { precision: precision, delimiter: NUMBER_FORMAT_DELIMITERS.fetch(separator_part, ",") }
  end

  UNFILTERABLE_TYPES = %w[File Header GridColumns Calculation].freeze

  scope :writable, -> { where(read_only: false) }
  scope :visible, -> { where.not(field_type: HIDDEN_FIELDS) }
  scope :calculations, -> { where(field_type: "Calculation") }
  scope :not_calculations, -> { where.not(field_type: "Calculation") }
  # Internal fields are those that are setup by CapHive for SEBI reporting etc. Not changable by the company
  scope :internal, -> { where(internal: true) }
  scope :not_internal, -> { where(internal: false) }
  scope :regulatory, -> { where.not(reg_env: [nil, ""]) }
  scope :not_regulatory, -> { where(reg_env: [nil, ""]) }
  scope :for_env, ->(env) { where(reg_env: env) }
  scope :filterable, -> { where(filter_in_search: true).where.not(field_type: UNFILTERABLE_TYPES) }

  # An option field keeps its whole choice list in one comma-separated meta_data string, and
  # admins naturally type "Individual, HUF, LLP". Without this, " HUF" becomes the option's
  # value as well as its label, so the space is saved into json_fields and every exact-match
  # consumer (the register_cf_ransacker filters, search_custom_fields, satisfies_condition?
  # and its JS twin) stops matching the row.
  #
  # Blank entries are kept. A leading "," or " ," is the idiom for "start this dropdown
  # empty" — dropping it would promote the first real choice to the default and silently
  # record an answer nobody gave.
  before_validation :normalize_option_meta_data

  # Only for the option types: meta_data means something different for every other field type
  # (Ruby for Calculation, "precision,separator" for NumberField, an ISO currency for Money,
  # "skill: true, sector: X" tags for File) and must be left exactly as typed.
  def normalize_option_meta_data
    return unless OPTION_FIELD_TYPES.include?(field_type)
    return if meta_data.blank?

    normalized = parse_options(meta_data).join(",")
    # Never let normalisation empty out a field that had something in it — that would trip
    # meta_data_present_for_option_types on input this used to accept.
    self.meta_data = normalized if normalized.present?
  end

  # The option list as the screens should render it. Use this rather than splitting meta_data
  # at the call site: it strips each choice while preserving the intentional blank one, and it
  # is safe on a nil meta_data.
  def options
    parse_options(meta_data)
  end

  validate :meta_data_kosher?, if: -> { field_type == "Calculation" }
  validate :meta_data_present_for_option_types
  validate :meta_data_currency_valid?, if: -> { field_type == "Money" }
  validate :name_normalizes_to_non_blank
  validate :validation_rules_consistent, if: -> { validation_rules.present? && VALID_FIELD_TYPES.include?(field_type) }

  def meta_data_kosher?
    errors.add(:meta_data, "You cannot do CRUD operations in meta_data") if meta_data.downcase.match?(SAFE_EVAL_REGEX)
  end

  def meta_data_present_for_option_types
    return unless OPTION_FIELD_TYPES.include?(field_type)

    errors.add(:meta_data, "must provide at least one option for #{field_type}") if meta_data.blank?
  end

  def meta_data_currency_valid?
    return if meta_data.blank?

    errors.add(:meta_data, "must be a valid ISO currency code, e.g. USD") if Money::Currency.find(meta_data.strip).nil?
  end

  # meta_data holds an ISO currency code (e.g. "USD") that overrides the model's own
  # currency when displaying a Money field. Blank meta_data falls back to model.currency.
  def money_currency(model)
    meta_data.presence&.strip || (model.currency if model.respond_to?(:currency))
  end

  def name_normalizes_to_non_blank
    return if name.blank?

    errors.add(:name, "produces an empty field key after normalization") if FormCustomField.to_name(name).blank?
  end

  def validation_rules_consistent
    rules = validation_rules.with_indifferent_access

    text_keys      = %w[min_length max_length pattern format error_message unique]
    numeric_keys   = %w[min_value max_value integer_only error_message unique]
    date_keys      = %w[min_date max_date error_message]
    selection_keys = %w[min_selections max_selections error_message]
    file_keys      = %w[allowed_extensions max_size_mb error_message]

    allowed_keys = case field_type
                   when "TextField", "TextArea"   then text_keys
                   when "NumberField", "Money"    then numeric_keys
                   when "DateField"               then date_keys
                   when "MultiSelect", "CheckBox" then selection_keys
                   when "File"                    then file_keys
                   else                                []
                   end

    return if allowed_keys.empty? # field type (e.g. Calculation, Header) carries no validation rules

    invalid_keys = rules.keys - allowed_keys
    errors.add(:validation_rules, "contains invalid keys for #{field_type}: #{invalid_keys.join(', ')}") if invalid_keys.any?

    case field_type
    when "TextField", "TextArea"
      validate_min_max_rule(rules, "min_length", "max_length")
      if rules["pattern"].present?
        begin
          Regexp.new(rules["pattern"])
        rescue RegexpError => e
          errors.add(:validation_rules, "pattern is not a valid regex: #{e.message}")
        end
      end
      errors.add(:validation_rules, "format must be one of: #{VALID_FORMATS.join(', ')}") if rules["format"].present? && VALID_FORMATS.exclude?(rules["format"])
    when "NumberField", "Money"
      validate_min_max_rule(rules, "min_value", "max_value")
    when "DateField"
      validate_date_rule_values(rules)
    when "MultiSelect", "CheckBox"
      validate_min_max_rule(rules, "min_selections", "max_selections")
    end
  end

  validate :read_only_and_required, if: -> { read_only && required }
  def read_only_and_required
    errors.add(:read_only, "Read only fields cannot be required")
  end

  validate :condition_on_custom_field, if: -> { condition_on.present? }
  def condition_on_custom_field
    # Only investor.category and investor_kyc.kyc_type standard fields can be used as condition_on
    if (form_type.name == "Investor" && condition_on == "category") ||
       (form_type.name == "InvestorKyc" && condition_on == "kyc_type")
      # Do nothing
    else
      # Check if the field is a custom field, as we can have custom fields only dependent on other custom fields
      parent_field = form_type.form_custom_fields.find { |fcf| fcf.name == condition_on }
      errors.add(:condition_on, "#{name} can be applied only on existing custom fields") if parent_field.nil?
    end
  end

  # This is to ensure that a field cannot be dependent on another field that is itself dependent on another conditional field
  # This is to prevent a chain of dependencies that can lead to complex and unmanageable conditions.
  validate :condition_two_level_max, if: -> { condition_on.present? }
  def condition_two_level_max
    parent_field = form_type.form_custom_fields.find { |fcf| fcf.name == condition_on }
    if parent_field.present? && parent_field.condition_on.present?
      grandparent_field = form_type.form_custom_fields.find { |fcf| fcf.name == parent_field.condition_on }
      errors.add(:condition_on, "#{name} cannot be dependent on a field that is itself dependent on another conditional field (more than two levels)") if grandparent_field.present? && grandparent_field.condition_on.present?
    end
  end

  def initialize(*)
    super
    self.field_type ||= "TextField"
  end

  before_create :set_default_values
  def set_default_values
    self.name = FormCustomField.to_name(name)
    # The Label box says "leave blank to derive from name" but submits "", which ||= used to keep.
    # Store what human_label was already showing for "" so the screens and upload template don't change.
    if label.nil?
      self.label = name.humanize
    elsif label.blank?
      self.label = name.humanize.titleize
    end
  end

  def renderer
    RENDERERS[field_type.to_sym]
  end

  def show_to_user(user)
    show_user_ids.blank? || show_user_ids.split(",").include?(user.id.to_s)
  end

  def human_label
    label.presence || name.humanize.titleize
  end

  # File fields whose meta_data marks them as sector skill prompts
  # (e.g. "skill: true, sector: D2C"). Single source of truth for the tag check —
  # used by SupportAgent#skill_for_sector and agent config health checks, which
  # must agree on what counts as a skill field.
  def skill_tagged?
    field_type == "File" && meta_data.to_s.match?(/skill/i)
  end

  # This is no longer applicable as name cannot be changed on the UI
  # after_commit :change_name_job, on: :update, if: :saved_change_to_name?

  # def change_name_job
  #   FcfNameChangeJob.perform_later(id, previous_changes[:name].first)
  # end

  def change_name(old_name)
    # Loop thru all the records
    klass = form_type.name.constantize
    Rails.logger.debug { "Changing name from #{old_name} to #{name} for #{form_type.name}" }

    klass.where(entity_id: form_type.entity_id).where.not(properties: {}).find_each do |record|
      # Replace the name value with the old name value
      record.properties[name] = record.properties[old_name]
      record.properties.delete(old_name)
      # Save the record without callbacks
      record.update_column(:properties, record.properties)
    end
  end

  def form_class(current_user = nil)
    css_class = "fcf"
    css_class += read_only && current_user&.curr_role == "investor" ? " hidden_form_field" : ""
    if condition_on.present?
      css_class += " conditional #{form_type.name.underscore}_properties_#{condition_on} #{form_type.name.underscore}_#{condition_on}"
      css_class += " #{condition_state}"
    end
    css_class
  end

  def data_attributes
    if condition_on.present?
      "data-match-value='#{condition_params}' data-match-criteria='#{condition_criteria}' data-mandatory='#{required}'"
    else
      "data-mandatory='#{required}'"
    end
  end

  def self.to_name(header)
    header.strip.titleize.squeeze(" ").tr(" ", "_").underscore.gsub(/[^0-9A-Za-z_]/, '').squeeze("_")
  end

  def self.json_fields_key(header, model, _form_type_id)
    form_type = model.entity.form_types.where(name: model.class.name).first
    form_type.form_custom_fields.find_by(name: to_name(header))&.id
  end

  private

  # Splits a comma-separated option list and trims each choice. Deliberately does NOT
  # compact_blank — see normalize_option_meta_data for why the empty choice has to survive.
  def parse_options(value)
    value.to_s.split(",").map(&:strip)
  end

  def validate_min_max_rule(rules, min_key, max_key)
    min = rules[min_key]
    max = rules[max_key]
    return unless min.present? && max.present?

    errors.add(:validation_rules, "#{min_key} must be less than or equal to #{max_key}") if min.to_d > max.to_d
  end

  def validate_date_rule_values(rules)
    %w[min_date max_date].each do |key|
      val = rules[key]
      next if val.blank? || val == "today"

      begin
        Date.parse(val.to_s)
      rescue ArgumentError
        errors.add(:validation_rules, "#{key} must be a valid ISO date or 'today'")
      end
    end

    min = rules["min_date"]
    max = rules["max_date"]
    return unless min.present? && max.present? && min != "today" && max != "today"

    begin
      errors.add(:validation_rules, "min_date must be before max_date") if Date.parse(min.to_s) > Date.parse(max.to_s)
    rescue ArgumentError
      nil
    end
  end
end
