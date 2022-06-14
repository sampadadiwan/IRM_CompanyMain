class FormTypesController < ApplicationController
  before_action :set_form_type, only: %i[show edit update destroy]

  # GET /form_types or /form_types.json
  def index
    @form_types = policy_scope(FormType)
  end

  # GET /form_types/1 or /form_types/1.json
  def show; end

  # GET /form_types/new
  def new
    @form_type = FormType.new
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
    respond_to do |format|
      if @form_type.save
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
    respond_to do |format|
      if @form_type.update(form_type_params)
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
    params.require(:form_type).permit(:name, form_custom_fields_attributes: %i[id name position field_type meta_data required has_attachment _destroy])
  end
end
