class CustomGridViewsController < ApplicationController
  before_action :set_custom_grid_view, only: %w[show edit update destroy update_column_sequence]
  skip_before_action :verify_authenticity_token, only: %i[update_column_sequence]

  def show
    fetch_grid_field_names
  end

  def edit
    fetch_grid_field_names
  end

  def update
    result = UpdateCustomGridView.wtf?(params:, custom_grid_view: @custom_grid_view)
    respond_to do |format|
      if result.success?
        format.html { redirect_to custom_grid_view_url(@custom_grid_view), notice: "Custom Grid View is updated." }
      else
        format.html { redirect_to custom_grid_view_url(@custom_grid_view), alert: "Custom Grid View update has failed." }
      end
    end
  end

  def update_column_sequence
    permitted_params = params.permit(:index, :key)
    index = permitted_params[:index].to_i
    key = permitted_params[:key]

    grid_view_preference = @custom_grid_view.grid_view_preferences.find_by(name: key)

    if grid_view_preference
      grid_view_preference.sequence = index + 1

      if grid_view_preference.save
        respond_to do |format|
          format.json { head :no_content }
        end
      else
        respond_to do |format|
          format.json { render json: { error: 'Failed to update sequence' }, status: :unprocessable_entity }
        end
      end
    else
      respond_to do |format|
        format.json { render json: { error: 'Grid view preference not found' }, status: :not_found }
      end
    end
  end

  def configure
    custom_grid_view = CreateDefaultCustomGridView.new(params[:form_type_id]).find_or_create
    authorize custom_grid_view
    redirect_to custom_grid_view_path(custom_grid_view)
  end

  private

  def fetch_grid_field_names
    @standard_column_fields = @custom_grid_view.owner.name.constantize::STANDARD_COLUMNS.values.map(&:to_s)
    @custom_field_names = @custom_grid_view.owner.form_custom_fields.where.not(field_type: "GridColumns").pluck(:name).map(&:to_s)
  end

  def set_custom_grid_view
    @custom_grid_view = CustomGridView.find(params[:id])
    authorize @custom_grid_view
  end
end
