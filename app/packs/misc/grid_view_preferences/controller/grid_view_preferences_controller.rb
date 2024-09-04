class GridViewPreferencesController < ApplicationController
  before_action :set_grid_view_preference, only: %i[destroy update_column_sequence]
  skip_before_action :verify_authenticity_token, only: %i[update_column_sequence]
  after_action :verify_authorized, except: %i[configure_grids]

  def create
    parent = find_parent
    column_name = GridViewPreference.get_column_name(parent, params[:key])
    grid_view_preference = parent.grid_view_preferences.find_by(key: params[:key])

    if grid_view_preference
      respond_to do |format|
        format.html { redirect_to configure_grids_grid_view_preferences_path(owner_type: parent.class.name, owner_id: parent.id), alert: "This column is already selected." }
      end
    else
      grid_view_preference = parent.grid_view_preferences.build(
        key: params[:key],
        name: column_name,
        entity_id: parent.entity_id
      )

      respond_to do |format|
        if grid_view_preference.save
          format.html { redirect_to configure_grids_grid_view_preferences_path(owner_type: parent.class.name, owner_id: parent.id), notice: "Custom Grid View is successfully modified." }
        else
          format.html { redirect_to configure_grids_grid_view_preferences_path(owner_type: parent.class.name, owner_id: parent.id), alert: "Custom Grid View failed to modify." }
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
      format.html { redirect_to configure_grids_grid_view_preferences_path(owner_type: @grid_view_preference.owner.class.name, owner_id: @grid_view_preference.owner.id), notice: 'Custom Grid View is successfully modified.' }
      format.json { head :no_content }
    end
  end

  def configure_grids
    @parent = find_parent
    model_class = begin
      @parent.name.constantize
    rescue StandardError
      @parent.model.constantize
    end
    @field_options = model_class::STANDARD_COLUMNS
    form_type = FormType.find_by(entity_id: current_user.entity_id, name: model_class.to_s)
    @custom_field_names = form_type.form_custom_fields.where.not(field_type: "GridColumns").pluck(:name).map(&:to_s) if form_type.present?
    @field_options = (@field_options.map { |name, value| [name, value] } + Array(@custom_field_names).map { |name| [name.humanize, "custom_fields.#{name}"] }).to_h
  end

  private

  def find_parent
    owner_type = params[:owner_type]
    owner_id = params[:owner_id]

    if owner_type.present? && owner_id.present?
      owner_type.constantize.find(owner_id)
    else
      raise "Parent not found"
    end
  end

  def set_grid_view_preference
    @grid_view_preference = GridViewPreference.find(params[:id])
    authorize @grid_view_preference
  end
end
