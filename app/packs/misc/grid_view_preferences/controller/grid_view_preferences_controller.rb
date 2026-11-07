class GridViewPreferencesController < ApplicationController
  # L14 — what grid columns belong to: a form type or a report (the only owners stored in production)
  OWNER_TYPES = %w[FormType Report].freeze

  before_action :set_grid_view_preference, only: %i[destroy update_column_sequence show edit update]
  # D19 — columns are added in the shared columns editor (grid_columns/_editor); the old new/create forms are gone
  skip_before_action :verify_authenticity_token, only: %i[update_column_sequence]
  # M15 — configure_grids is authorized too (GridViewPreferencePolicy#configure_grids?)
  after_action :verify_authorized

  def show; end

  def edit; end

  def update
    respond_to do |format|
      if @grid_view_preference.update(edit_params)
        # D19 — back to Configure Grids with this column open on the right, so the list there is current
        format.html do
          owner = @grid_view_preference.owner
          redirect_to configure_grids_grid_view_preferences_path(owner_type: owner.class.name, owner_id: owner.id, show_id: @grid_view_preference.id),
                      notice: "Grid column updated."
        end
        format.json { render json: { message: "Updated successfully" }, status: :ok }
      else
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @grid_view_preference.errors, status: :unprocessable_entity }
      end
    end
  end

  def update_column_sequence
    permitted_params = params.permit(:index, :key)
    index = permitted_params[:index].to_i
    if @grid_view_preference
      # acts_as_list uses 1-based indexing for insert_at
      @grid_view_preference.insert_at(index + 1)

      respond_to do |format|
        format.json { head :no_content }
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
    # M15 — the screen lists the parent's columns and custom fields, so the parent must be the user's
    # firm's; any user of that firm may open it (the Decision did not require company admin). Checked
    # on a column for the parent, as #create does - not built through the association, which would put
    # an unsaved column into the list the screen shows (M15-4, M15-H)
    authorize GridViewPreference.new(owner: @parent, entity_id: @parent.entity_id), :configure_grids?
    # D19 — the same columns editor as the side panel, embedded, for this form type or report (its saved columns,
    # or the record type's standard ones); saved rows also get Show / Edit / Delete
    # (openspec/changes/grid-columns-inline-settings — H16, H17, E26, E27, X20)
    @context = GridColumnsContext.for_owner(@parent)
    raise ActiveRecord::RecordNotFound, "This record type has no grid columns" unless @context

    @rows = helpers.grid_columns_rows(@context)
    @can_save = policy(GridViewPreference.new(owner: @context.owner, entity_id: @context.entity.id)).inline_columns?
  end

  private

  def find_parent
    permitted_params = params.permit(:owner_type, :owner_id)
    owner_type = permitted_params[:owner_type] || params[:grid_view_preference][:owner_type]
    owner_id = permitted_params[:owner_id] || params[:grid_view_preference][:owner_id]

    if owner_type.present? && owner_id.present?
      # L14 — grid columns belong to a form type or a report (the only owners stored in production); an
      # unknown name is a 404, not a 500 (L14-10)
      owner_class = ApplicationRecord.model_class_from_param(owner_type, allowed: OWNER_TYPES)
      raise ActiveRecord::RecordNotFound, "Unknown owner type" unless owner_class

      owner_class.find(owner_id)
    else
      raise "Parent not found"
    end
  end

  def set_grid_view_preference
    @grid_view_preference = GridViewPreference.find(params[:id])
    authorize @grid_view_preference
  end

  # D19 — the Edit form shows the heading without its "; css" part: store it as the columns editor does (blank or
  # the column's own name → no override; the name's alignment suffix kept)
  def edit_params
    attrs = grid_view_preference_params
    attrs[:label] = GridColumnsSave.stored_label(attrs[:label], @grid_view_preference.name) if attrs.key?(:label)
    attrs
  end

  def grid_view_preference_params
    params.require(:grid_view_preference).permit(:name, :key, :data_type, :label, :selected, :sequence, :derived_field, :alignment)
  end
end
