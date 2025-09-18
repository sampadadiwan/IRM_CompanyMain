class GridViewPreference < ApplicationRecord
  # Associations
  belongs_to :owner, polymorphic: true

  # ActsAsList for ordering preferences within the same owner
  acts_as_list column: :sequence, scope: :owner

  # Validations
  validates :key, presence: true
  validates :alignment, length: { maximum: 12 }, allow_blank: true

  # Callbacks
  after_save :touch_entity
  after_destroy :touch_entity
  before_save :set_data_type, if: -> { data_type.blank? }

  # Scope to filter out derived fields
  scope :not_derived, -> { where("derived_field IS NOT TRUE") }

  # Default data type if not inferred
  DEFAULT_DATA_TYPE = "String".freeze

  # Returns the human-readable name for a given key
  # Tries to lookup in the parent's STANDARD_COLUMNS, otherwise humanizes the key
  def self.get_column_name(parent, key)
    begin
      column_name = parent.name.constantize::STANDARD_COLUMNS.key(key)
    rescue NameError
      column_name = parent.model.constantize::STANDARD_COLUMNS.key(key)
    end

    return column_name if column_name.present?

    # Fallback: strip "custom_fields." prefix and humanize
    key.gsub("custom_fields.", "").humanize
  end

  # Assigns the appropriate data type before saving
  def set_data_type
    self.data_type = custom_data_type
  end

  # Determines the data type for the column
  # Returns DEFAULT_DATA_TYPE if the type can't be inferred
  def custom_data_type
    return data_type if data_type.present?

    if key.include?("custom_fields.")
      DEFAULT_DATA_TYPE
    else
      begin
        model_columns_hash = owner.model_columns_hash
        # lookup the column type in the model's columns hash i.e DB
        column = model_columns_hash[key] || model_columns_hash["#{key}_cents"]
        # If the column is not found, fallback to the default data type
        # If the column is found, use its type
        column&.type.to_s.capitalize.presence || DEFAULT_DATA_TYPE
      rescue StandardError
        # If the model is not found or any other error occurs, fallback to the default data type
        DEFAULT_DATA_TYPE
      end
    end
  end

  def name_with_alignment
    if alignment.present?
      "#{label.presence || name}; #{alignment}"
    else
      label.presence || name
    end
  end

  def key_with_alignment
    if alignment.present?
      "#{key}; #{alignment}"
    else
      key
    end
  end

  private

  # Touches the associated entity to trigger cache invalidation or updated timestamps
  # Only applicable if the owner is a FormType and has an associated entity
  # rubocop:disable Rails/SkipsModelValidations
  def touch_entity
    owner.entity.touch if owner.is_a?(FormType) && owner.entity.present?
  end
  # rubocop:enable Rails/SkipsModelValidations
end
