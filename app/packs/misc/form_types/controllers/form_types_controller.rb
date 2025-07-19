class FormTypesController < ApplicationController
  before_action :set_form_type, only: %i[show edit update destroy clone rename_fcf configure_grids]

  # GET /form_types or /form_types.json
  def index
    authorize(FormType)
    @form_types = policy_scope(FormType)
  end

  # GET /form_types/1 or /form_types/1.json
  def show; end

  def clone
    if @form_type.entity_id == current_user.entity_id
      redirect_to form_type_path(@form_type), alert: "Cannot clone form type in the same entity."
    else
      ActiveRecord::Base.connected_to(role: :writing) do
        @clone = @form_type.deep_clone(current_user.entity_id)
      end
      redirect_to form_type_path(@clone), notice: "Form type was successfully cloned."
    end
  end

  # GET /form_types/new
  def new
    @form_type = params[:form_type].present? ? FormType.new(form_type_params) : FormType.new
    @form_type.entity_id ||= current_user.entity_id
    authorize(@form_type)
  end

  # GET /form_types/1/edit
  def edit; end

  # POST /form_types or /form_types.json
  def create
    @form_type = FormType.new(form_type_params)
    @form_type.entity_id ||= current_user.entity_id
    authorize(@form_type)
    allowed = true
    begin
      unless current_user.support?
        # We dont allow non support users to update calculations
        @form_type.form_custom_fields.each do |fcf|
          allowed = false if fcf.field_type == "Calculation"
        end
      end
      saved = allowed ? @form_type.save : false
    rescue ActiveRecord::RecordNotUnique
      @form_type.errors.add(:base, "Duplicate names detected. Please ensure all names are unique.")
      @form_type.dup_cf_names?
      saved = false
    end

    respond_to do |format|
      if saved
        format.html { redirect_to form_type_url(@form_type), notice: "Form type was successfully created." }
        format.json { render :show, status: :created, location: @form_type }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @form_type.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /form_types/1 or /form_types/1.json
  def update
    allowed = true
    begin
      unless current_user.support? || Rails.env.local?
        # We dont allow non support users to update calculations
        params["form_type"]["form_custom_fields_attributes"].each_value do |fcf|
          if fcf["field_type"] == "Calculation"
            allowed = false
            @form_type.errors.add(:position, "#{fcf['position']}, calculation cannot be updated by non support user.")
          end
        end
      end

      saved = allowed ? @form_type.update(form_type_params) : false
    rescue ActiveRecord::RecordNotUnique
      @form_type.errors.add(:base, "Duplicate names detected. Please ensure all names are unique.")
      @form_type.dup_cf_names?
      saved = false
    end

    respond_to do |format|
      if saved
        format.html { redirect_to form_type_url(@form_type), notice: "Form type was successfully updated." }
        format.json { render :show, status: :ok, location: @form_type }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @form_type.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /form_types/1 or /form_types/1.json
  def destroy
    @form_type.destroy

    respond_to do |format|
      format.html { redirect_to form_types_url, notice: "Form type was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def rename_fcf
    old_name = params[:old_name]
    new_name = params[:new_name]
    fcf = @form_type.form_custom_fields.where(name: old_name).last
    if fcf
      fcf.name = new_name
      fcf.save
      fcf.change_name(old_name)
      notice = "Field name and data successfully changed."
    else
      notice = "Field name #{old_name} not found."
    end
    redirect_to form_type_url(@form_type), notice:
  end

  def configure_grids
    @standard_column_fields = @form_type.name.constantize::STANDARD_COLUMNS
    @custom_field_names = @form_type.form_custom_fields.where.not(field_type: "GridColumns").pluck(:name).map(&:to_s)
    @field_options = (@standard_column_fields.map { |name, value| [name, value] } + @custom_field_names.map { |name| [name.humanize, "custom_fields.#{name}"] }).to_h
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_form_type
      # This is to ensure that the form_custom_fields are loaded with all rich text fields to avoid n+1 queries                 
    @form_type = FormType.includes(form_custom_fields: :rich_text_info).find(params[:id])                 
    authorize(@form_type)
  end

  # Only allow a list of trusted parameters through.
  def form_type_params
    params.require(:form_type).permit(:name, :tag, :entity_id, form_custom_fields_attributes: %i[id name position help_text field_type meta_data required read_only has_attachment show_user_ids step label _destroy condition_on condition_criteria condition_params condition_state internal info])
  end
end
