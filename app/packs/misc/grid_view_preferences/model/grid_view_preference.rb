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

  # Ensure we have some data type for the column
  before_save :set_data_type, if: -> { data_type.blank? }
  def set_data_type
    self.data_type = custom_data_type
  end

  DEFAULT_DATA_TYPE = "String".freeze
  def custom_data_type
    if data_type.present?
      data_type
    elsif key.include?("custom_fields.")
      DEFAULT_DATA_TYPE
    else
      begin
        column = owner.model.constantize.columns_hash[key].presence || owner.model.constantize.columns_hash["#{key}_cents"]
        if column.nil?
          nil
        else
          column.type.to_s.capitalize.presence || DEFAULT_DATA_TYPE
        end
      rescue StandardError
        DEFAULT_DATA_TYPE
      end
    end
  end

  private

  # rubocop:disable Rails/SkipsModelValidations
  def touch_entity
    owner.entity.touch if owner.is_a?(FormType) && owner.entity.present?
  end
  # rubocop:enable Rails/SkipsModelValidations
end
