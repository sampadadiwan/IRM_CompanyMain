module WithCustomField
  extend ActiveSupport::Concern

  included do
    attr_accessor :cached_custom_fields
    # This is used to skip the before_save callback, used when we are generating thousands of account_entries as this slows it down considerably
    attr_accessor :skip_cf_before_save

    attribute :json_fields, :json, default: {}
    alias_attribute :properties, :json_fields

    # This is used to get the form type
    belongs_to :form_type, optional: true

    # This is used to get the form custom fields
    has_many :form_custom_fields, through: :form_type

    # Ensure that the form type is set, if not already present
    before_save :setup_form_type, if: -> { skip_cf_before_save != true }

    # This is done so that if there are any custom_fields which are calculations, then they are run and computed
    before_save :perform_all_calculations, if: -> { skip_cf_before_save != true && form_custom_fields && form_custom_fields.calculations.present? }

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
      Arel.sql("(json_fields ->> '#{key}')")
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

    # This is used to create the query for json fields, used in the above ransacker
    def self.json_fields_query(query)
      return unless query

      query = query.try(:permit!).try(:to_h) unless query.is_a?(Hash)
      query.each_with_object({}) do |(k, v), obj|
        if k.starts_with?('json_fields.')
          field = k.split('json_fields.').last
          operation = Ransack::Predicate.detect_and_strip_from_string!(field)

          raise ArgumentError, "No valid predicate for #{field}" unless operation

          (obj[:c] ||= []) << {
            a: {
              '0' => {
                name: 'json_fields',
                ransacker_args: field
              }
            },
            p: operation,
            v: [v]
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
    val = eval(fcf.meta_data)
    json_fields[fcf.name] = val
    val
  end

  def custom_fields
    @cached_custom_fields ||= OpenStruct.new(json_fields)
    @cached_custom_fields
  end

  def custom_fields_with_td
    struct = {}
    # We convert DateField to Date, Money to Money object, so that the template can use it
    form_type.form_custom_fields.visible.each do |cf|
      if cf.field_type == 'DateField'
        struct[cf.name] = Date.parse(json_fields[cf.name]) if json_fields[cf.name].present?
      elsif cf.field_type == 'Money'
        struct[cf.name] = Money.new(json_fields[cf.name].to_d * 100, currency) if json_fields[cf.name].present?
      else
        struct[cf.name] = json_fields[cf.name]
      end
    end
    TemplateDecorator.decorate(OpenStruct.new(struct))
  end

  # rubocop:enable Style/OpenStructUse

  def custom_calcs
    CustomCalcs.new(self, custom_calculations)
  end

  def custom_calcs_with_td
    TemplateDecorator.decorate(custom_calcs)
  end

  # rubocop:disable Rails/SkipsModelValidations
  def ensure_json_fields
    return unless form_type && json_fields

    updated = false
    form_type.form_custom_fields.visible.each do |cf|
      self.json_fields ||= {}
      unless self.json_fields.key?(cf.name)
        self.json_fields[cf.name] ||= nil
        updated = true
      end
    end

    update_column(:json_fields, self.json_fields) if updated
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

    form_custom_fields.select do |fcf|
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

  private

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

  def respond_to_missing? *_args
    true
  end
end
