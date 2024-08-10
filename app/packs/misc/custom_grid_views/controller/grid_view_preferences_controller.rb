class GridViewPreferencesController < ApplicationController
  before_action :set_grid_view_preference, only: %i[destroy update_column_sequence]
  skip_before_action :verify_authenticity_token, only: %i[update_column_sequence]

  def create
    form_type = FormType.find(params[:form_type_id])
    column_name = form_type.get_column_name(params[:key])

    grid_view_preference = form_type.grid_view_preferences.find_by(key: params[:key])
    if grid_view_preference
      respond_to do |format|
        format.html { redirect_to configure_grids_form_type_path(form_type), alert: "This column is already selected." }
      end
    else
      grid_view_preference = form_type.grid_view_preferences.build(key: params[:key], name: column_name, entity_id: form_type.entity_id)
      respond_to do |format|
        if grid_view_preference.save
          format.html { redirect_to configure_grids_form_type_path(form_type), notice: "Custom Grid View is successfully modified." }
        else
          format.html { redirect_to configure_grids_form_type_path(form_type), alert: "Custom Grid View failed to modify." }
        end
      end
    end
    authorize grid_view_preference
  end

  def update_column_sequence
    permitted_params = params.permit(:index, :key)
    index = permitted_params[:index].to_i
    permitted_params[:key]
    if @grid_view_preference
      @grid_view_preference.sequence = index + 1

      if @grid_view_preference.save
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

  def destroy
    @grid_view_preference.destroy
    respond_to do |format|
      format.html { redirect_to configure_grids_form_type_path(@grid_view_preference.owner), notice: 'Custom Grid View is successfully modified.' }
      format.json { head :no_content }
    end
  end

  def set_grid_view_preference
    @grid_view_preference = GridViewPreference.find(params[:id])
    authorize @grid_view_preference
  end
end
