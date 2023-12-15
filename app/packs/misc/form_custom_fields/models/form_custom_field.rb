class FormCustomField < ApplicationRecord
  belongs_to :form_type
  acts_as_list scope: :form_type

  enum :step,  { one: 1, two: 2, three: 3, end: 100 }

  normalizes :name, with: ->(name) { name.strip.delete(" ").underscore.gsub(%r{[^0-9A-Za-z_]}, '') }
  validates :name, :show_user_ids, length: { maximum: 100 }
  validates :label, length: { maximum: 254 }
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

  def human_label
    label.presence || name.humanize.titleize
  end

  after_commit :change_name_job, on: :update, if: :saved_change_to_name?

  def change_name_job
    FcfNameChangeJob.perform_later(id, previous_changes[:name].first)
  end

  def change_name(old_name)
    # Loop thru all the records
    form_type.name.constantize.where(entity_id: form_type.entity_id).find_each do |record|
      record.properties[name] = record.properties[old_name]
      record.properties.delete(old_name)
      record.save(validate: false)
    end
  end
end
