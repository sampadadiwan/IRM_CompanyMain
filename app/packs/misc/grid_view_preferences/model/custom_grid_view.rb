class CustomGridView < ApplicationRecord
  belongs_to :owner, polymorphic: true
  has_many :grid_view_preferences, -> { order(:sequence) }, dependent: :destroy
  delegate :entity_id, to: :owner

  def grid_preferences
    sorted_preferences = grid_view_preferences.order(:sequence)
    sorted_preferences.each_with_object({}) do |preference, hash|
      hash[preference.id] = preference.name
    end
  end

  def selected_columns
    grid_view_preferences.order(:sequence)
                         .pluck(:name, :key)
                         .to_h
  end

  def get_column_name(key)
    column_name = owner.name.constantize::STANDARD_COLUMNS.key(key)
    return column_name if column_name.present?

    key.gsub("custom_fields.", "").humanize
  end
end
