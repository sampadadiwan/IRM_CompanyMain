class FormTypesController < ApplicationController
  before_action :set_form_type, only: %i[show edit update destroy clone]

  # GET /form_types or /form_types.json
  def index
    @form_types = policy_scope(FormType)
  end

  # GET /form_types/1 or /form_types/1.json
  def show; end

  def clone
    @clone = @form_type.deep_clone(current_user.entity_id)
    redirect_to form_type_path(@clone), notice: "Form type was successfully cloned."
  end

  # GET /form_types/new
  def new
    @form_type = params[:form_type].present? ? FormType.new(form_type_params) : FormType.new
    @form_type.entity_id = current_user.entity_id
    authorize(@form_type)
  end

  # GET /form_types/1/edit
  def edit; end

  # POST /form_types or /form_types.json
  def create
    @form_type = FormType.new(form_type_params)
    @form_type.entity_id = current_user.entity_id
    authorize(@form_type)

    begin
      saved = @form_type.save
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
      saved = @form_type.update(form_type_params)
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

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_form_type
    @form_type = FormType.find(params[:id])
    authorize(@form_type)
  end

  # Only allow a list of trusted parameters through.
  def form_type_params
    params.require(:form_type).permit(:name, form_custom_fields_attributes: %i[id name position help_text field_type meta_data required read_only has_attachment show_user_ids step label _destroy condition_on condition_criteria condition_params condition_state])
  end
end
