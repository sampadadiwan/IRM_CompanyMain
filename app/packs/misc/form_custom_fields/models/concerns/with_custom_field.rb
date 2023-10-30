module WithCustomField
  extend ActiveSupport::Concern

  included do
    belongs_to :form_type, optional: true
    has_many :form_custom_fields, through: :form_type
    serialize :properties, type: Hash
  end

  def map_custom_fields
    form_custom_fields.index_by(&:name)
  end

  # rubocop:disable Style/OpenStructUse
  def custom_fields
    OpenStruct.new(properties)
  end
  # rubocop:enable Style/OpenStructUse
end
