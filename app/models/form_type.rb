class FormType < ApplicationRecord
  has_many :form_custom_fields, -> { order(position: :asc) }, inverse_of: :form_type, dependent: :destroy
  accepts_nested_attributes_for :form_custom_fields, reject_if: :all_blank, allow_destroy: true
end
