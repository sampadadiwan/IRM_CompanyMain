class FormTypesController < ApplicationController
  before_action :set_form_type, only: %i[show edit update destroy clone rename_fcf configure_grids add_regulatory_fields generate_upload_xlsx edit_step_labels update_step_labels]

  # GET /form_types or /form_types.json
  def index
    authorize(FormType)
    @form_types = policy_scope(FormType)
    @bread_crumbs = { 'Custom Forms': nil }
  end

  # GET /form_types/1 or /form_types/1.json
  def show
    @bread_crumbs = { 'Custom Forms': form_types_path, "#{@form_type.name} #{@form_type.tag}": nil }
  end

  def generate_upload_xlsx
    respond_to do |format|
      format.xlsx do
        response.headers['Content-Disposition'] = "attachment; filename=\"#{@form_type}.xlsx\""
      end
    end
  end

  # POST /form_types/1/clone — M25: support only, into the user's current firm; authorized by
  # set_form_type (FormTypePolicy#clone?). M25-1, M25-2, M25-H
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
    @form_type.tag ||= "Default"
    authorize(@form_type)
    @bread_crumbs = { 'Custom Forms': form_types_path, New: nil }
  end

  # GET /form_types/1/edit
  def edit
    @bread_crumbs = { 'Custom Forms': form_types_path, "#{@form_type.name} #{@form_type.tag}": form_type_path(@form_type), Edit: nil }
  end

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
    begin
      # Calculation fields hold Ruby; only CapHive support may change them (shared with the custom fields side
      # panel — FormType#calculation_change_allowed?, openspec/changes/grid-columns-inline-settings D14)
      fields = params.dig("form_type", "form_custom_fields_attributes")&.values || []
      # C2 (OWASP 2026-11) — pass the form type so ids of stored Calculation fields are refused too
      allowed = FormType.calculation_change_allowed?(current_user, fields, @form_type)
      unless allowed
        fields.select { |fcf| fcf["field_type"] == "Calculation" }.each do |fcf|
          @form_type.errors.add(:position, "#{fcf['position']}, calculation cannot be updated by non support user.")
        end
        # An existing Calculation field named only by id gets no per-field message above, so say it once
        @form_type.errors.add(:base, "Calculation fields can only be changed by CapHive support.") if @form_type.errors.empty?
      end

      saved = allowed ? update_form_type : false
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

  # GET /form_types/1/edit_step_labels
  def edit_step_labels
    @bread_crumbs = { 'Custom Forms': form_types_path, "#{@form_type.name} #{@form_type.tag}": form_type_path(@form_type), 'Step Labels': nil }
  end

  # PATCH /form_types/1/update_step_labels
  def update_step_labels
    if @form_type.update(step_labels_params)
      respond_to do |format|
        format.turbo_stream  # renders update_step_labels.turbo_stream.erb
        format.html { redirect_to form_type_path(@form_type), notice: "Step labels updated." }
      end
    else
      respond_to do |format|
        format.turbo_stream  # re-renders form with errors in the panel
        format.html { render :edit_step_labels, status: :unprocessable_entity }
      end
    end
  end

  def add_regulatory_fields
    reg_env = params[:reg_env]
    back_to = params[:back_to] || form_type_path(@form_type)
    if reg_env.blank?
      redirect_to back_to, alert: "Regulatory environment must be specified."
      return
    end

    @form_type.reg_env = reg_env

    if @form_type.save
      redirect_to back_to, notice: "#{reg_env} Reporting fields added successfully to #{@form_type.name} #{@form_type.tag.presence || @form_type.id}"
    else
      redirect_to back_to, alert: "Failed to add Reporting fields for #{reg_env} to #{@form_type.name} #{@form_type.tag.presence || @form_type.id}"
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

  # The custom form editor sends reordered=1 once its list was dragged: every field's position then comes from the
  # list's order, already renumbered in the browser, and must be saved as sent. Left to acts_as_list, each field saved
  # in turn would shift the others it passes and scramble the order. Any other save is unchanged.
  def update_form_type
    return @form_type.update(form_type_params) unless params[:reordered] == "1"

    FormCustomField.acts_as_list_no_update { @form_type.update(form_type_params) }
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_form_type
    # This is to ensure that the form_custom_fields are loaded with all rich text fields to avoid n+1 queries
    @form_type = FormType.includes(form_custom_fields: :rich_text_info).find(params[:id])
    authorize(@form_type)
  end

  def step_labels_params
    params.require(:form_type).permit(step_labels: {})
  end

  # Only allow a list of trusted parameters through.
  def form_type_params
    vr_keys = FormCustomField::VALIDATION_RULE_KEYS.map { |k| :"vr_#{k}" }
    params.require(:form_type).permit(:name, :tag, :entity_id, :reg_env, step_labels: {}, form_custom_fields_attributes: %i[id name position help_text field_type meta_data required read_only has_attachment show_user_ids step label _destroy condition_on condition_criteria condition_params condition_state internal info reg_env filter_in_search] + vr_keys)
  end
end
