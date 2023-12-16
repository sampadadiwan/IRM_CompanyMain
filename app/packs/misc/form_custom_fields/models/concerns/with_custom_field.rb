module WithCustomField
  extend ActiveSupport::Concern

  included do
    attribute :json_fields, :json, default: {}
    alias_attribute :properties, :json_fields

    belongs_to :form_type, optional: true
    has_many :form_custom_fields, through: :form_type
  end

  def map_custom_fields
    form_custom_fields.index_by(&:name)
  end

  def custom_fields
    OpenStruct.new(json_fields)
  end

  # rubocop:enable Style/OpenStructUse
end
