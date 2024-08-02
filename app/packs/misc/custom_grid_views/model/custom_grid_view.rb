class CustomGridView < ApplicationRecord
  belongs_to :owner, polymorphic: true
  has_many :grid_view_preferences, dependent: :destroy
  delegate :entity_id, to: :owner

  def grid_preferences
    sorted_preferences = grid_view_preferences.order(:sequence)
    sorted_preferences.each_with_object({}) do |preference, hash|
      hash[preference.id] = preference.name
    end
  end

  def selected_columns
    selected_preferences = grid_view_preferences.where(selected: true).order(:sequence)
    selected_preferences.each_with_object({}) do |preference, hash|
      hash[preference.name] = preference.key
    end
  end

  def owner_id_must_be_nil
    errors.add(:owner_id, "must be nil") unless owner_id.nil?
  end
end
