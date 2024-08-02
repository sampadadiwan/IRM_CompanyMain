class UpdateCustomGridView < Trailblazer::Operation
  step :map_grid_fields
  step :save_custom_grid_view
  left :handle_errors

  private

  def map_grid_fields(_ctx, params:, custom_grid_view:, **)
    selected_column_ids = params.dig("custom_grid_view", "grid_view_preferences") || []
    # rubocop:disable Rails/SkipsModelValidations
    custom_grid_view.grid_view_preferences.update_all(selected: false)
    # rubocop:enable Rails/SkipsModelValidations

    selected_column_ids.each do |id|
      preference = custom_grid_view.grid_view_preferences.find_by(id:)
      preference.update(selected: true)
    end
    true
  end

  def save_custom_grid_view(_ctx, custom_grid_view:, **)
    custom_grid_view.save
  end

  def handle_errors(ctx, custom_grid_view:, **)
    ctx[:errors] = custom_grid_view.errors
  end
end
