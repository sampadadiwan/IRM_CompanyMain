class FormCustomFieldsController < ApplicationController
  before_action :set_form_custom_field, only: %i[show edit update destroy]

  # GET /form_custom_fields or /form_custom_fields.json
  def index
    @form_custom_fields = policy_scope(FormCustomField)
    @form_custom_fields = @form_custom_fields.where(form_type_id: params[:form_type_id]) if params[:form_type_id].present?
    @form_custom_fields = @form_custom_fields.order(:position)
  end

  # GET /form_custom_fields/1 or /form_custom_fields/1.json
  def show
    authorize @form_custom_field
  end

  # GET /form_custom_fields/new
  def new
    @form_custom_field = FormCustomField.new
    authorize @form_custom_field
  end

  # GET /form_custom_fields/1/edit
  def edit
    authorize @form_custom_field
  end

  # POST /form_custom_fields or /form_custom_fields.json
  def create
    @form_custom_field = FormCustomField.new(form_custom_field_params)
    authorize @form_custom_field

    respond_to do |format|
      if @form_custom_field.save
        format.html { redirect_to form_custom_field_url(@form_custom_field), notice: "Form custom field was successfully created." }
        format.json { render :show, status: :created, location: @form_custom_field }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @form_custom_field.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /form_custom_fields/1 or /form_custom_fields/1.json
  def update
    authorize @form_custom_field

    respond_to do |format|
      if @form_custom_field.update(form_custom_field_params)
        # back_to is a plain param set when editing from a parent page (e.g. FormType show).
        # Only accept relative paths to prevent open redirect.
        back_to     = params[:back_to].presence
        destination = (back_to&.start_with?("/") ? back_to : nil) || form_custom_field_url(@form_custom_field)
        format.html { redirect_to destination, notice: "Form custom field was successfully updated." }
        format.turbo_stream  # renders update.turbo_stream.erb: replaces row + clears panel
        format.json { render :show, status: :ok, location: @form_custom_field }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.turbo_stream  # renders update.turbo_stream.erb: shows errors in panel
        format.json { render json: @form_custom_field.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /form_custom_fields/1 or /form_custom_fields/1.json
  def destroy
    authorize @form_custom_field
    @form_custom_field.destroy

    respond_to do |format|
      format.html { redirect_to form_custom_fields_url, notice: "Form custom field was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_form_custom_field
    @form_custom_field = FormCustomField.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def form_custom_field_params
    vr_keys = FormCustomField::VALIDATION_RULE_KEYS.map { |k| :"vr_#{k}" }
    params.require(:form_custom_field).permit(:name, :field_type, :required, :read_only, :form_type_id, :info, :reg_env, :meta_data, :label, :help_text, :position, :step, :show_user_ids, :condition_on, :condition_criteria, :condition_params, :condition_state, :filter_in_search, *vr_keys)
  end
end
