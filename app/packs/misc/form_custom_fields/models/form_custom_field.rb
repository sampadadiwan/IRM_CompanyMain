class FormCustomField < ApplicationRecord
  belongs_to :form_type
  acts_as_list scope: :form_type

  RENDERERS = { Money: "/form_custom_fields/display/money", DateField: "/form_custom_fields/display/date" }.freeze

  scope :writable, -> { where(read_only: false) }

  def renderer
    RENDERERS[field_type.to_sym]
  end
end
