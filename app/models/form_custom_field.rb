class FormCustomField < ApplicationRecord
  belongs_to :form_type
  has_many_attached :files, service: :amazon, dependent: :destroy
end
