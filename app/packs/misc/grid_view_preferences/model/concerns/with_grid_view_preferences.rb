# Included in Report and FormType as they both have grid_view_preferences
# This module provides functionality to manage grid view preferences for models.
# It allows models to have a customizable grid view by storing user preferences for columns and their order.
# The module includes methods to retrieve selected columns and grid columns based on user preferences.
# It also establishes a one-to-many relationship with the GridViewPreference model, ensuring that preferences are destroyed if the owner is destroyed.
module WithGridViewPreferences
  extend ActiveSupport::Concern

  included do
    # Establishes a one-to-many relationship with grid_view_preferences
    # The preferences are destroyed if the owner is destroyed
    has_many :grid_view_preferences, as: :owner, dependent: :destroy
  end

  def selected_columns
    # Memoizes and retrieves selected columns ordered by sequence
    # Converts preferences into a hash with label/name as key and key as value
    @selected_columns ||= grid_view_preferences.order(:sequence)
                                               .to_h { |preference| [preference.label.presence || preference.name, preference.key] }

    # Fallback to standard columns if no preferences are found
    @selected_columns ||= model::STANDARD_COLUMNS.reject { |k, _| k.blank? }
    @selected_columns
  end

  def ag_selected_columns
    # Memoizes and retrieves grid columns ordered by sequence
    # Filters and maps preferences into a hash with label, key, and data_type
    @ag_selected_columns ||= grid_view_preferences.order(:sequence).filter_map do |preference|
      custom_data_type = preference.custom_data_type
      # Skips the preference if custom_data_type is nil (commented out for now)

      {
        label: preference.label.presence || preference.name, # Use label if present, otherwise name
        key: preference.key, # The unique key for the column
        data_type: custom_data_type.presence # Include data_type if present
      }
    end

    # Fallback to default grid columns if no preferences are found
    @ag_selected_columns ||= model.ag_grids_default_columns
    @ag_selected_columns
  end

  def model
    # Abstract method to be implemented in the including class
    # Raises an error if not implemented
    raise NotImplementedError, "You must implement the model method in your class"
  end

  def model_columns_hash
    # Returns the columns hash of the model's class
    # This method is used to retrieve the columns of the model
    model.constantize.columns_hash
  end
end
