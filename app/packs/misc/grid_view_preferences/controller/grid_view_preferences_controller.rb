class GridViewPreferencesController < ApplicationController
  # L14 — what grid columns belong to: a form type or a report (the only owners stored in production)
  OWNER_TYPES = %w[FormType Report].freeze

  before_action :set_grid_view_preference, only: %i[destroy update_column_sequence show edit update]
  skip_before_action :verify_authenticity_token, only: %i[update_column_sequence]
  # M15 — configure_grids is authorized too (GridViewPreferencePolicy#configure_grids?)
  after_action :verify_authorized

  def create
    # Find the Report or FormType based on the owner_type and owner_id
    parent = find_parent
    # Get the column name based on the key provided in the params
    column_name = if grid_view_preference_params[:derived_field]
                    grid_view_preference_params[:label]
                  else
                    GridViewPreference.get_column_name(parent, grid_view_preference_params[:key])
                  end

    grid_view_preference = parent.grid_view_preferences.find_by(key: params[:key])

    if grid_view_preference
      # M15 — permission on the existing column before saying anything about it
      authorize grid_view_preference
      respond_to do |format|
        format.html { redirect_to configure_grids_grid_view_preferences_path(owner_type: parent.class.name, owner_id: parent.id), alert: "This column is already selected." }
      end
    else

      # Setup the grid_view_preference object
      grid_view_preference = parent.grid_view_preferences.build(
        key: grid_view_preference_params[:key],
        name: column_name,
        entity_id: parent.entity_id,
        label: grid_view_preference_params[:label],
        data_type: grid_view_preference_params[:data_type],
        derived_field: grid_view_preference_params[:derived_field]
      )
      # M15 — ask permission on the built column (its parent's firm, company admin) before the save, so
      # a refused column is never written (M15-3, M15-H); it used to be saved first and authorized after
      authorize grid_view_preference

      respond_to do |format|
        if grid_view_preference.save
          format.html { redirect_to configure_grids_grid_view_preferences_path(owner_type: parent.class.name, owner_id: parent.id), notice: "Custom Grid View is successfully modified." }
        else
          format.html { redirect_to configure_grids_grid_view_preferences_path(owner_type: parent.class.name, owner_id: parent.id), alert: "Custom Grid View failed to modify." }
        end
      end
    end
  end

  def new
    @grid_view_preference = GridViewPreference.new
    @grid_view_preference.owner_id = params[:grid_view_preference][:owner_id]
    @grid_view_preference.owner_type = params[:grid_view_preference][:owner_type]
    @grid_view_preference.entity_id = current_user.entity_id
    @grid_view_preference.derived_field = true
    authorize @grid_view_preference

    @frame = params[:turbo_frame] || "new_grid_view_preference"
    if params[:turbo]
      render turbo_stream: [
        turbo_stream.replace(@frame, partial: "grid_view_preferences/form", locals: { grid_view_preference: @grid_view_preference, frame: @frame })
      ]
    end
  end

  def show; end

  def edit; end

  def update
    respond_to do |format|
      if @grid_view_preference.update(grid_view_preference_params)
        format.html { redirect_to @grid_view_preference, notice: "Grid View Preference was successfully updated." }
        format.json { render json: { message: "Updated successfully" }, status: :ok }
      else
        format.html { render :edit, alert: "Failed to update Grid View Preference." }
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
    model_class = begin
      @parent.name.constantize
    rescue StandardError
      @parent.model.constantize
    end

    # Initialize field_options with standard columns
    @field_options = model_class::STANDARD_COLUMNS
    # Add the ADDITIONAL_COLUMNS if they are defined
    @field_options = @field_options.merge(model_class::ADDITIONAL_COLUMNS) if model_class.const_defined?(:ADDITIONAL_COLUMNS)

    # The related classes whose columns are offered too (e.g. a commitment's investor), keyed by relationship
    add_classes = if model_class.const_defined?(:ADDITIONAL_COLUMNS_FROM)
                    model_class::ADDITIONAL_COLUMNS_FROM.index_with { |rel| model_class.reflect_on_association(rel).klass }
                  else
                    {}
                  end
    # Custom field names for the model and every related class, loaded together instead of a
    # FormType find_by plus a pluck per class
    custom_names = grid_custom_field_names([model_class, *add_classes.values])

    add_classes.each do |add_relationship, add_class|
      # Merge additional columns from the class into field_options but add a prefix to the keys and values
      @field_options = @field_options.merge(add_class::STANDARD_COLUMNS.transform_keys { |key| "#{add_relationship.humanize}.#{key}" }.transform_values { |value| "#{add_relationship}.#{value}" })
      # Merge the custom columns of the add_class
      names = custom_names[add_class.to_s]
      @field_options = @field_options.merge(names.to_h { |name| ["#{add_relationship.humanize}.#{name.humanize}", "#{add_relationship}.custom_fields.#{name}"] }) if names
    end

    # Then the model's own custom fields
    names = custom_names[model_class.to_s]
    @field_options = (@field_options.map { |name, value| [name, value] } + names.map { |name| [name.humanize, "custom_fields.#{name}"] }).to_h if names

    # Clean up the labels in field_options for display in the dropdown
    @field_options = @field_options.transform_keys { |k| k.split(";").first.strip }
  end

  private

  # Grid-selectable custom field names per class name, for the current user's firm, in one query
  # for the form types and one for their fields.
  #
  # Same results as the per-class lookups it replaced:
  #   - a class with no FormType is absent from the hash (the caller then adds nothing for it);
  #   - with duplicate FormTypes of one name, the lowest id wins, as find_by returned it;
  #   - fields come in the association's position order, minus "GridColumns" fields and fields
  #     with no field_type (SQL's field_type != 'GridColumns' never matched NULL).
  #
  # @param classes [Array<Class>]
  # @return [Hash{String => Array<String>}] e.g. { "Investor" => ["pan", "risk_rating"] }
  def grid_custom_field_names(classes)
    form_types = FormType.where(entity_id: current_user.entity_id, name: classes.map(&:to_s))
                         .order(:id).includes(:form_custom_fields)
    form_types.each_with_object({}) do |form_type, names|
      # Keep the first (lowest id) form type per name
      next if names.key?(form_type.name)

      names[form_type.name] = form_type.form_custom_fields
                                       .reject { |f| f.field_type.nil? || f.field_type == "GridColumns" }
                                       .map { |f| f.name.to_s }
    end
  end

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

  def grid_view_preference_params
    params.require(:grid_view_preference).permit(:name, :key, :data_type, :label, :selected, :sequence, :derived_field, :alignment)
  end
end
