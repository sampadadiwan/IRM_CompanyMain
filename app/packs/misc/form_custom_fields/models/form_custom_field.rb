class FormCustomField < ApplicationRecord
  belongs_to :form_type
  acts_as_list scope: :form_type

  validates :name, :show_user_ids, length: { maximum: 50 }
  validates :field_type, length: { maximum: 20 }

  RENDERERS = { Money: "/form_custom_fields/display/money", DateField: "/form_custom_fields/display/date" }.freeze

  scope :writable, -> { where(read_only: false) }

  before_save :set_default_values
  def set_default_values
    self.name = name.strip.downcase
  end

  def renderer
    RENDERERS[field_type.to_sym]
  end

  def show_to_user(user)
    show_user_ids.blank? || show_user_ids.split(",").include?(user.id.to_s)
  end
end
