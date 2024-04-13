module WithCustomField
  extend ActiveSupport::Concern

  included do
    attr_accessor :cached_custom_fields

    attribute :json_fields, :json, default: {}
    alias_attribute :properties, :json_fields

    belongs_to :form_type, optional: true, dependent: :destroy
    has_many :form_custom_fields, through: :form_type

    # Scope to search for custom fields Useage: InvestorKyc.search_custom_fields("nationality", "Indian")
    scope :search_custom_fields, lambda { |key, value|
      where("JSON_UNQUOTE(json_fields -> ?) = ?", "$.#{key}", value)
    }

    # This is search for Json Fields via ransack
    # Useage:  InvestorKyc.ransack(InvestorKyc.json_fields_query("json_fields.nationality_cont" => "India")).result
    ransacker :json_fields, args: %i[parent ransacker_args] do |parent, args|
      Rails.logger.debug { "parent: #{parent} args: #{args}" }
      key = args
      Arel::Nodes::InfixOperation.new('->>', parent.table[:json_fields],
                                      Arel::Nodes.build_quoted("$.#{key}"))
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

  def map_custom_fields
    form_custom_fields.visible.index_by(&:name)
  end

  def custom_calculations
    form_custom_fields.calculations
  end

  def perform_custom_calculation(calc)
    eval(calc)
  end

  def custom_fields
    @cached_custom_fields ||= OpenStruct.new(json_fields)
    @cached_custom_fields
  end
  # rubocop:enable Style/OpenStructUse

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
      json_fields ||= {}
      unless json_fields.key?(cf.name)
        json_fields[cf.name] ||= nil
        updated = true
      end
    end
    save(validate: false) if updated
    updated
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
    @model.perform_custom_calculation(calc.meta_data) if calc
  end

  def respond_to_missing? *_args
    true
  end
end
