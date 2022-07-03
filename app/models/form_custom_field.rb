# == Schema Information
#
# Table name: form_custom_fields
#
#  id             :integer          not null, primary key
#  name           :string(50)
#  field_type     :string(20)
#  required       :boolean
#  form_type_id   :integer          not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  meta_data      :text(65535)
#  has_attachment :boolean          default("0")
#  position       :integer
#  help_text      :text(65535)
#

class FormCustomField < ApplicationRecord
  belongs_to :form_type
  acts_as_list scope: :form_type
end
