class AdhaarEsignsController < ApplicationController
  before_action :set_adhaar_esign, only: %i[show edit update destroy completed]
  after_action :verify_authorized, except: %i[index search]

  # GET /adhaar_esigns or /adhaar_esigns.json
  def index
    @investor = nil
    @adhaar_esigns = policy_scope(AdhaarEsign)
    if params[:investor_id]
      @investor = Investor.find(params[:investor_id])
      @adhaar_esigns = @adhaar_esigns.where(investor_id: params[:investor_id])
    end

    @adhaar_esigns = @adhaar_esigns.where(verified: params[:verified] == "true") if params[:verified].present?

    @adhaar_esigns = @adhaar_esigns.includes(:investor, :entity)
  end

  # GET /adhaar_esigns/1 or /adhaar_esigns/1.json
  def show; end

  # This is a one off callback from digio, once the document signing is completed
  # The id sent back is the id of the AdhaarEsign which triggered the signing request
  # @see AdhaarEsign
  def completed
    if params[:status] == "success"
      AdhaarEsignCompletedJob.perform_later(@adhaar_esign.id)
      redirect_to @adhaar_esign.owner, notice: "Adhaar eSign was successfull"
    else
      redirect_to @adhaar_esign.owner, notice: "Adhaar eSign was not successfull, please retry again."
    end
  end

  def digio_webhook
    @adhaar_esign = AdhaarEsign.where(esign_doc_id: params[:digio_doc_id]).first
    AdhaarEsignCompletedJob.perform_later(@adhaar_esign.id) if @adhaar_esign && (params[:status] == "success")

    respond_to do |format|
      format.json { render json: [], status: :ok }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_adhaar_esign
    @adhaar_esign = AdhaarEsign.find(params[:id])
    authorize(@adhaar_esign)
  end

  # Only allow a list of trusted parameters through.
  def adhaar_esign_params
    params.require(:adhaar_esign).permit
  end
end
