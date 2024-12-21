class GridViewPreference < ApplicationRecord
  belongs_to :owner, polymorphic: true
  acts_as_list column: :sequence, scope: :owner
  validates :key, presence: true

  after_save :touch_entity
  after_destroy :touch_entity

  scope :not_derived, -> { where("derived_field IS NOT TRUE") }

  def self.get_column_name(parent, key)
    begin
      column_name = parent.name.constantize::STANDARD_COLUMNS.key(key)
    rescue NameError
      column_name = parent.model.constantize::STANDARD_COLUMNS.key(key)
    end
    return column_name if column_name.present?

    key.gsub("custom_fields.", "").humanize
  end

  DEFAULT_DATA_TYPE = "String".freeze
  def custom_data_type
    if data_type.present?
      data_type
    elsif key.include?("custom_fields.")
      DEFAULT_DATA_TYPE
    else
      column = owner.name.constantize.columns_hash[key]
      if column.nil?
        nil
      else
        column.type.to_s.capitalize.presence || DEFAULT_DATA_TYPE
      end
    end
  end

  private

  def touch_entity
    owner.entity.touch if owner.is_a?(FormType) && owner.entity.present?
  end
end
