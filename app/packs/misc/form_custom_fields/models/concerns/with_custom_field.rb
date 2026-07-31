module WithCustomField
  extend ActiveSupport::Concern

  included do
    attr_accessor :cached_custom_fields
    # This is used to skip the before_save callback, used when we are generating thousands of account_entries as this slows it down considerably
    attr_accessor :skip_cf_before_save

    # Tracks ransacker names dynamically registered for filterable custom fields.
    # class_attribute ensures each model class gets its own mutable copy.
    class_attribute :_cf_ransacker_names, default: []
    class_attribute :_cf_ransacker_labels, default: {}

    # Prepend a singleton wrapper so ransackable_attributes and human_attribute_name
    # automatically include any dynamically registered CF ransackers.
    singleton_class.prepend(Module.new do
      def ransackable_attributes(auth_object = nil)
        (defined?(super) ? super : []) + Array(_cf_ransacker_names)
      end

      def human_attribute_name(attribute, options = {})
        _cf_ransacker_labels[attribute.to_s] || super
      end
    end)

    attribute :json_fields, :json, default: {}
    def json_fields
      super || {}
    end
    alias_attribute :properties, :json_fields

    # This is used to get the form type
    belongs_to :form_type, optional: true

    # This is used to get the form custom fields
    has_many :form_custom_fields, through: :form_type

    # Ensure that the form type is set, if not already present
    before_save :setup_form_type, if: -> { skip_cf_before_save != true }

    # This is done so that if there are any custom_fields which are calculations, then they are run and computed
    before_save :perform_all_calculations, if: -> { skip_cf_before_save != true && form_custom_fields && form_custom_fields.calculations.present? }

    validate :check_required_custom_fields, if: -> { form_type.present? && skip_cf_before_save != true }
    validate :check_custom_field_formats,   if: -> { form_type.present? && skip_cf_before_save != true }

    # Scope to search for custom fields Useage: InvestorKyc.search_custom_fields("nationality", "Indian")
    if Rails.env.test?
      scope :search_custom_fields, lambda { |key, value|
        where("json_extract(json_fields, ?) = ?", "$.#{key}", value)
      }
    else
      scope :search_custom_fields, lambda { |key, value|
        where("JSON_UNQUOTE(json_fields -> ?) = ?", "$.#{key}", value)
      }
    end

    # This is search for Json Fields via ransack
    # Useage:  InvestorKyc.ransack(InvestorKyc.json_fields_query("json_fields.nationality_cont" => "India")).result
    ransacker :json_fields, args: %i[parent ransacker_args] do |parent, args|
      Rails.logger.debug { "parent: #{parent} args: #{args}" }
      key = args
      Arel::Nodes::InfixOperation.new('->>', parent.table[:json_fields],
                                      Arel::Nodes.build_quoted("$.#{key}"))
    end

    # Custom ransacker for searching JSON fields
    ransacker :json_field_value, args: [:key] do |_parent, args|
      key = args.first
      # lease_connection.quote escapes the key (including embedded quotes) so a
      # custom-field name cannot break out of the SQL string literal
      # (lease_connection is the Rails 8.1 replacement for the soft-deprecated .connection)
      Arel.sql("(json_fields ->> #{ActiveRecord::Base.lease_connection.quote(key.to_s)})")
    end

    # This is used to calculate the start of financial year based on the month offset set in models json fields
    def start_of_financial_year_date(end_date = nil, nil_if_not_set: false)
      # In some cases we may want to return nil if the end_date is not set and nil_if_not_set is true (See KpiCumulative)
      if end_date.nil? && nil_if_not_set
        nil
      else
        end_date ||= Time.zone.today
        # Some funds/entities/portcos want to set the start of the financial year to Jan some to April, this allows for that.
        month_offset_for_fy = json_fields && json_fields["month_offset_for_fy"].present? ? json_fields["month_offset_for_fy"].to_i : 3
        date = end_date.month > month_offset_for_fy ? end_date.beginning_of_year : (end_date.beginning_of_year - 1.year)
        (date + month_offset_for_fy.months)
      end
    end

    def setup_form_type
      # Ensure that the form type is set, if not already present
      self.form_type ||= entity.form_types.where(name: self.class.name).last
    end

    # This is used to perform all the custom calculations
    def perform_all_calculations
      Rails.logger.debug { "#{self.class.name}: perform_all_calculations called" }
      custom_calculations.each do |fcf|
        perform_custom_calculation(fcf)
      end
      # Reset the cached custom fields, so that when custom_fields is called, it will use the latest calculations
      @cached_custom_fields = nil
    end

    # Registers a named ransacker for a filterable custom field so it appears in
    # the Ransack attribute dropdown alongside standard attributes.
    # Idempotent — calling twice with the same name is a no-op.
    def self.register_cf_ransacker(field_name, label: nil)
      name = field_name.to_s
      unless _ransackers.key?(name)
        # Use parent.table[:json_fields] so the column is fully qualified with the
        # model's table name — prevents "ambiguous column" errors when the query
        # JOINs other tables that also have a json_fields column (e.g. investor_kycs).
        ransacker(name.to_sym) do |parent|
          Arel::Nodes::InfixOperation.new('->>', parent.table[:json_fields], Arel::Nodes.build_quoted("$.#{name}"))
        end
      end
      self._cf_ransacker_names = (_cf_ransacker_names + [name]).uniq
      self._cf_ransacker_labels = _cf_ransacker_labels.merge(name => label) if label
    end

    # This is used to create the query for json fields, used in the above ransacker
    def self.json_fields_query(query)
      return unless query

      query = query.try(:permit!).try(:to_h) unless query.is_a?(Hash)
      query.each_with_object({}) do |(k, v), obj|
        if k.starts_with?('json_fields.')
          field = k.split('json_fields.').last
          operation = Ransack::Predicate.detect_and_strip_from_string!(field)

          raise ArgumentError, "No valid predicate for #{field}" unless operation

          (obj["c"] ||= []) << {
            "a" => {
              "0" => {
                "name" => "json_fields",
                "ransacker_args" => field
              }
            },
            "p" => operation,
            "v" => { "0" => { "value" => v } }
          }
        else
          obj[k] = v
        end
      end
    end
  end

  def custom_field_label(field_name)
    map_custom_fields[field_name]&.label || field_name.humanize
  end

  def map_custom_fields
    @map_custom_fields ||= form_custom_fields.visible.index_by(&:name)
  end

  def custom_calculations
    @custom_calculations ||= form_custom_fields.calculations
  end

  def perform_custom_calculation(fcf)
    if fcf.meta_data.present?
      # meta_data is a Ruby calculation eval-ed here. FormCustomField#meta_data_kosher? guards
      # it at write time (only for Calculation fields); guard again at the eval boundary so paths
      # that skip validation (update_column, imports) cannot execute arbitrary code.
      val = eval(ApplicationRecord.safe_eval!(fcf.meta_data, context: "FormCustomField##{fcf.id} meta_data"))
      json_fields[fcf.name] = val
      val
    end
  end

  def custom_fields
    # Memoised per record instance. CustomFieldsProxy is cheap to build (no method
    # definitions), but we still cache it so repeated calls within a request don't
    # allocate a new wrapper object each time.
    @custom_fields ||= CustomFieldsProxy.new(json_fields)
  end

  def custom_fields_with_td
    struct = {}
    currencies = []
    # We convert DateField to Date, Money to Money object, so that the template can use it
    form_type.form_custom_fields.visible.each do |cf|
      if cf.field_type == 'DateField'
        struct[cf.name] = Date.local_parse(json_fields[cf.name]) if json_fields[cf.name].present?
      elsif cf.field_type == 'Money'
        # Fetch all valid currencies for the entity
        currencies = if currencies.blank?
                       res = entity.exchange_rates.pluck(:from).map(&:downcase) << entity.currency.downcase
                       res << fund.currency.downcase if respond_to?(:fund) && fund&.currency.present?
                       res
                     else
                       currencies
                     end
        # if meta_data has currency and it is a valid currency then use that as the currency for Money objects
        if cf.meta_data.present? && currencies.include?(cf.meta_data.strip.downcase)
          struct[cf.name] = Money.new(json_fields[cf.name].to_d * 100, cf.meta_data.strip.upcase) if json_fields[cf.name].present?
        elsif respond_to?(:currency) && currency.present?
          # If the model has a currency attribute, use that as the currency for Money objects.
          struct[cf.name] = Money.new(json_fields[cf.name].to_d * 100, currency) if json_fields[cf.name].present?
        elsif json_fields[cf.name].present?
          # no currency set, so we use Entity Currency
          # we dont expect the entity currency to be nil
          struct[cf.name] = Money.new(json_fields[cf.name].to_d * 100, entity.currency)
        end
      else
        struct[cf.name] = json_fields[cf.name]
      end
    end
    # struct keys are dynamic (come from form_custom_fields at runtime), so CustomFieldsProxy
    # is used here for the same reason as custom_fields — Data.define requires fixed keys.
    TemplateDecorator.decorate(CustomFieldsProxy.new(struct))
  end

  def custom_calcs
    CustomCalcs.new(self, custom_calculations)
  end

  def custom_calcs_with_td
    TemplateDecorator.decorate(custom_calcs)
  end

  def ensure_json_fields
    return unless form_type && json_fields

    updated = false
    form_type.form_custom_fields.visible.each do |cf|
      self.json_fields ||= {}
      unless json_fields.key?(cf.name)
        json_fields[cf.name] ||= nil
        updated = true
      end
    end

    update_column(:json_fields, json_fields) if updated
    updated
  end
  # rubocop:enable Rails/SkipsModelValidations

  # This is used to get the required fields for the form type
  # It also checks for any conditions on the fields
  # and only returns the fields which are required based on the conditions
  # Example: If a field is required only if another field has a certain value
  # then it checks for that condition and returns the field only if the condition is met
  # Returns required fields for given type.
  # By default applies condition_on logic, but can ignore conditions to match DB query
  def required_fields_for(field_type: nil)
    json_fields || {}
    # Use form_type.form_custom_fields (direct has_many on FormType) to avoid loading
    # the has_many :through target on this model — see check_custom_field_formats for the
    # full explanation. Falls back to form_custom_fields only if form_type is not loaded.
    source = form_type&.form_custom_fields || form_custom_fields

    source.select do |fcf|
      next false unless fcf.required?
      next false if field_type && fcf.field_type != field_type

      debug_prefix = "#{fcf.name} (id=#{fcf.id}, type=#{fcf.field_type}, required=#{fcf.required?})"

      if fcf.condition_on.present?
        cond_val = json_fields[fcf.condition_on]
        Rails.logger.debug { "  -> Has condition_on: #{fcf.condition_on}, criteria=#{fcf.condition_criteria}, params=#{fcf.condition_params}, value_in_json=#{cond_val.inspect}" }
        if cond_val.present?
          result = satisfies_condition?(fcf, json_fields)
          Rails.logger.debug { "  -> #{debug_prefix} Condition evaluated, result=#{result ? 'including' : 'excluding'}" }
          result
        else
          Rails.logger.debug { "  -> #{debug_prefix} Driving field not set, result=including" }
          true
        end
      else
        Rails.logger.debug { "  -> #{debug_prefix} No condition_on, result=including" }
        true
      end
    end
  end

  def check_required_custom_fields
    required_fields_for.each do |fcf|
      next if fcf.field_type == "File" # File fields are stored as Documents, not json_fields; validated separately

      val = json_fields[fcf.name]
      msg = fcf.validation_rules&.dig("error_message").presence || "#{fcf.human_label} is required"
      errors.add(:base, msg) if val.blank?
    end
  end

  def check_custom_field_formats
    return unless form_type

    # Go through form_type.form_custom_fields (direct has_many on FormType) rather than the
    # has_many :through proxy on this model. When the owner is a new record, Rails autosave
    # tries to insert_record every item in the through-association's loaded target, which
    # raises HasManyThroughCantAssociateThroughHasOneOrManyReflection. Accessing via form_type
    # avoids populating this model's through-association cache.
    form_type.form_custom_fields.visible.not_calculations.each do |fcf|
      val = json_fields[fcf.name]
      next if val.blank?

      rules = (fcf.validation_rules || {}).with_indifferent_access
      error_msg = rules["error_message"].presence

      case fcf.field_type
      when "NumberField", "Money"
        validate_numeric_field(fcf, val, rules, error_msg)
      when "DateField"
        validate_date_field(fcf, val, rules, error_msg)
      when "TextField", "TextArea"
        validate_text_field(fcf, val, rules, error_msg)
      when "MultiSelect", "CheckBox"
        validate_selection_field(fcf, val, rules, error_msg)
      end

      validate_unique_field(fcf, val, error_msg) if rules["unique"]
    end
  end

  private

  def validate_numeric_field(fcf, val, rules, error_msg)
    unless /\A-?\d+(\.\d+)?\z/.match?(val.to_s)
      errors.add(:base, error_msg || "#{fcf.human_label} must be a number")
      return
    end
    num = val.to_d
    errors.add(:base, error_msg || "#{fcf.human_label} must be at least #{rules['min_value']}") if rules["min_value"].present? && num < rules["min_value"].to_d
    errors.add(:base, error_msg || "#{fcf.human_label} must be at most #{rules['max_value']}") if rules["max_value"].present? && num > rules["max_value"].to_d
    errors.add(:base, error_msg || "#{fcf.human_label} must be a whole number") if rules["integer_only"] && num != num.floor
  end

  def validate_date_field(fcf, val, rules, error_msg)
    date = Date.parse(val.to_s)
    min_date = resolve_date_rule(rules["min_date"])
    max_date = resolve_date_rule(rules["max_date"])
    errors.add(:base, error_msg || "#{fcf.human_label} cannot be before #{min_date}") if min_date && date < min_date
    errors.add(:base, error_msg || "#{fcf.human_label} cannot be after #{max_date}") if max_date && date > max_date
  rescue ArgumentError, TypeError
    errors.add(:base, error_msg || "#{fcf.human_label} must be a valid date")
  end

  def validate_text_field(fcf, val, rules, error_msg)
    str = val.to_s
    errors.add(:base, error_msg || "#{fcf.human_label} must be at least #{rules['min_length']} characters") if rules["min_length"].present? && str.length < rules["min_length"].to_i
    errors.add(:base, error_msg || "#{fcf.human_label} must be at most #{rules['max_length']} characters") if rules["max_length"].present? && str.length > rules["max_length"].to_i
    if rules["pattern"].present?
      begin
        errors.add(:base, error_msg || "#{fcf.human_label} format is invalid") unless str.match?(Regexp.new(rules["pattern"]))
      rescue RegexpError
        nil
      end
    end
    if rules["format"].present?
      pattern = FormCustomField::FORMAT_PATTERNS[rules["format"]]
      errors.add(:base, error_msg || "#{fcf.human_label} is not a valid #{rules['format']}") if pattern && !str.match?(pattern)
    end
  end

  def validate_selection_field(fcf, val, rules, error_msg)
    selections = val.is_a?(Array) ? val : val.to_s.split(",").map(&:strip).compact_blank
    count = selections.length
    errors.add(:base, error_msg || "#{fcf.human_label} requires at least #{rules['min_selections']} selection(s)") if rules["min_selections"].present? && count < rules["min_selections"].to_i
    errors.add(:base, error_msg || "#{fcf.human_label} allows at most #{rules['max_selections']} selection(s)") if rules["max_selections"].present? && count > rules["max_selections"].to_i
  end

  def validate_unique_field(fcf, val, error_msg)
    klass = self.class
    query = if Rails.env.test?
              klass.where(entity_id:).where("json_extract(json_fields, ?) = ?", "$.#{fcf.name}", val.to_s)
            else
              klass.where(entity_id:).where("JSON_UNQUOTE(json_fields -> ?) = ?", "$.#{fcf.name}", val.to_s)
            end
    exists = query.where.not(id: id || 0).exists?
    errors.add(:base, error_msg || "#{fcf.human_label} must be unique") if exists
  end

  def resolve_date_rule(val)
    return nil if val.blank?
    return Time.zone.today if val == "today"

    Date.parse(val.to_s)
  rescue ArgumentError
    nil
  end

  def satisfies_condition?(fcf, json_fields)
    actual_value = json_fields[fcf.condition_on]&.to_s&.downcase
    data_match_value = fcf.condition_params.to_s.downcase
    criteria = fcf.condition_criteria
    state = fcf.condition_state

    matched =
      if actual_value.present? && criteria == "contains"
        actual_value.include?(data_match_value) || data_match_value.include?(actual_value)
      elsif %w[gt lt gte lte].include?(criteria)
        if actual_value =~ /\A-?\d+(\.\d+)?\z/ && data_match_value =~ /\A-?\d+(\.\d+)?\z/
          num_val = actual_value.to_f
          num_match = data_match_value.to_f
          case criteria
          when "gt" then num_val > num_match
          when "lt" then num_val < num_match
          when "gte" then num_val >= num_match
          when "lte" then num_val <= num_match
          end
        else
          false
        end
      else
        actual_value == data_match_value
      end

    case [matched, criteria, state]
    when [true, "eq", "show"],
         [true, "contains", "show"],
         [false, "not_eq", "show"],
         [true, "gt", "show"],
         [true, "lt", "show"],
         [true, "gte", "show"],
         [true, "lte", "show"]
      true
    else
      false
    end
  end
end

# CustomFieldsProxy wraps the json_fields Hash to provide attribute-style access
# (e.g. record.custom_fields.some_field) without the cost of OpenStruct.
#
# Why not OpenStruct?
#   OpenStruct.new(hash) defines a getter/setter method on the instance's singleton
#   class for every key in the hash. With 200+ custom fields per KYC record, loading
#   a list page creates thousands of singleton-class method definitions — one for every
#   key on every record. These linger in memory and slow down method dispatch globally.
#
# Why not Struct or Data?
#   Both require all member names to be fixed at class-definition time, but json_fields
#   keys come from form_custom_fields at runtime and vary per entity. A dynamically
#   created Struct.new(*keys) would allocate a new anonymous class per record, which is
#   even worse. Unknown keys also raise NameError instead of returning nil.
#
# This proxy uses method_missing instead, so no methods are pre-defined. Access patterns
# supported across the codebase:
#   .field_name          — mailers, jobs, doc generators (method_missing)
#   .send(variable)      — capital_commitment_shared, portfolio_computations (method_missing)
#   [:symbol_key]        — fund_formula, run_formulas ([] with to_s normalisation)
#   ["string_key"]       — generate_aml_report_job ([] directly)
#   .present? / .blank?  — secondary_sales, offer jobs (explicit delegation to @hash)
#
# Unknown keys return nil, matching OpenStruct behaviour, so callers using &. or .present?
# guards continue to work without change.
class CustomFieldsProxy
  def initialize(hash)
    @hash = hash || {} # guard against nil json_fields on new records before before_save runs
  end

  # Normalise symbol keys to strings so [:nationality] and ["nationality"] both work.
  # json_fields is always stored and returned as a string-keyed Hash by ActiveRecord.
  def [](key)
    @hash[key.to_s]
  end

  # Explicit delegation — without these, present?/blank? would fall through to
  # method_missing and return nil, making .present? always truthy (non-nil).
  delegate :present?, to: :@hash

  delegate :blank?, to: :@hash

  # Lets callers use respond_to? guards before .send(variable_field_name).
  def respond_to_missing?(name, include_private = false)
    @hash.key?(name.to_s) || super
  end

  # Core of the proxy: look up the field name in the hash rather than defining a method.
  # Returns nil for unknown keys (OpenStruct parity) — no NoMethodError.
  def method_missing(name, *_args)
    @hash[name.to_s]
  end
end

# This is a class that is required for word templates which is used for document generation
# It allows the template to access the custom calculations that are defined in the form type
# Note templates use the sablon gem, that cannot call methods with params, hence we use the method_missing
class CustomCalcs
  attr_accessor :model, :custom_calcs

  def initialize(model, custom_calcs)
    @model = model
    @custom_calcs = custom_calcs
  end

  def method_missing(method_name, *_args, &)
    calc = @custom_calcs.find { |cf| cf.name == method_name.to_s }
    @model.perform_custom_calculation(calc) if calc
  end

  def respond_to_missing?(*_args)
    true
  end
end
