class ESignaturesController < ApplicationController
  before_action :set_e_signature, only: %i[show edit update destroy]

  # GET /e_signatures or /e_signatures.json
  def index
    @e_signatures = policy_scope(ESignature)
  end

  # GET /e_signatures/1 or /e_signatures/1.json
  def show; end

  # GET /e_signatures/new
  def new
    @e_signature = ESignature.new(e_signature_params)
    authorize @e_signature
  end

  # GET /e_signatures/1/edit
  def edit; end

  # POST /e_signatures or /e_signatures.json
  def create
    @e_signature = ESignature.new(e_signature_params)
    authorize @e_signature
    respond_to do |format|
      if @e_signature.save
        format.html { redirect_to e_signature_url(@e_signature), notice: "E signature was successfully created." }
        format.json { render :show, status: :created, location: @e_signature }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @e_signature.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /e_signatures/1 or /e_signatures/1.json
  def update
    respond_to do |format|
      if @e_signature.update(e_signature_params)
        format.html { redirect_to e_signature_url(@e_signature), notice: "E signature was successfully updated." }
        format.json { render :show, status: :ok, location: @e_signature }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @e_signature.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /e_signatures/1 or /e_signatures/1.json
  def destroy
    @e_signature.destroy

    respond_to do |format|
      format.html { redirect_to e_signatures_url, notice: "E signature was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_e_signature
    @e_signature = ESignature.find(params[:id])
    authorize @e_signature
  end

  # Only allow a list of trusted parameters through.
  def e_signature_params
    params.require(:e_signature).permit(:entity_id, :user_id, :label, :signature_type, :document_id, :notes, :status)
  end
end
