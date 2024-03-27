module WithCustomField
  extend ActiveSupport::Concern

  included do
    attribute :json_fields, :json, default: {}
    alias_attribute :properties, :json_fields

    belongs_to :form_type, optional: true
    has_many :form_custom_fields, through: :form_type
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
    OpenStruct.new(json_fields)
  end
  # rubocop:enable Style/OpenStructUse

  def custom_calcs
    CustomCalcs.new(self, custom_calculations)
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
    @model.perform_custom_calculation(calc.meta_data)
  end

  def respond_to_missing? *args
    true
  end
end
