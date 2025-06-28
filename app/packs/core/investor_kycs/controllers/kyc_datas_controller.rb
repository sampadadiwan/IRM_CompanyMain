class KycDatasController < ApplicationController
  before_action :set_kyc_data, only: %i[show toggle_approved]
  after_action :verify_authorized, except: %i[index search show]

  # GET /kyc_datas or /kyc_datas.json
  def index
    @kyc_datas = policy_scope(KycData).joins(:investor_kyc)
    authorize(KycData)
    @kyc_datas = @kyc_datas.where(investor_kyc_id: params[:investor_kyc_id])

    @kyc_datas = @kyc_datas.where(source: params[:source]) if params[:source].present?
    @pagy, @kyc_datas = pagy(@kyc_datas) if params[:all].blank?
    respond_to do |format|
      format.html
      format.turbo_stream
      format.json { render json: KycDataDatatable.new(params, kyc_datas: @kyc_datas) }
    end
  end

  def search
    query = params[:query]
    if query.present?

      entity_ids = [current_user.entity_id]

      @kyc_datas = KycData.filter(terms: { entity_id: entity_ids })
                          .query(query_string: { fields: KycDataIndex::SEARCH_FIELDS,
                                                 query:, default_operator: 'and' })
      @pagy, @kyc_datas = pagy(@kyc_datas.page(params[:page]).objects)

      render "index"
    else
      redirect_to kyc_datas_path(request.parameters)
    end
  end

  # GET /kyc_datas/1 or /kyc_datas/1.json or /kyc_datas/1.pdf
  def show
    authorize(@kyc_data)
    respond_to do |format|
      format.html { render "show" }
      format.json { render json: @kyc_data }
    end
  end

  # POST /kyc_datas or /kyc_datas.json
  def create; end

  def compare_ckyc_kra
    @ckyc_data = nil
    @kra_data = nil
    if params[:investor_kyc_id].present?
      @investor_kyc = InvestorKyc.find(params[:investor_kyc_id])
      @kyc_datas = policy_scope(KycData).where(investor_kyc_id: params[:investor_kyc_id])
      ActiveRecord::Base.connected_to(role: :writing) do
        if @investor_kyc.entity.entity_setting.ckyc_enabled?
          @ckyc_data = @kyc_datas.where(source: "ckyc").last
          @ckyc_data = CkycKraService.new.get_ckyc_data(@investor_kyc) if @ckyc_data.blank?
          authorize(@ckyc_data)
        end
        if @investor_kyc.entity.entity_setting.kra_enabled?
          @kra_data = @kyc_datas.where(source: "kra").last
          @kra_data = CkycKraService.new.get_kra_data(@investor_kyc) if @kra_data.blank?
          authorize(@kra_data)
        end
      end
    end

    alert = ""
    alert = "CKYC data not found" if @ckyc_data.blank? || @ckyc_data&.response.blank?
    alert += " KRA data not found" if @kra_data.blank? || @kra_data&.response.blank?

    respond_to do |format|
      if alert.present?
        format.html { render "compare_ckyc_kra", status: :unprocessable_entity, alert: }
      else
        format.html { render "compare_ckyc_kra" }
      end
    end
  end

  def generate_new
    respond_to do |format|
      @kyc_data = nil
      if params[:investor_kyc_id].present?
        @investor_kyc = InvestorKyc.find(params[:investor_kyc_id])
        @kyc_data = if params[:source] == "ckyc"
                      CkycKraService.new.get_ckyc_data(@investor_kyc)
                    else
                      CkycKraService.new.get_kra_data(@investor_kyc)
                    end
        authorize(@kyc_data)
        format.html { redirect_to compare_ckyc_kra_kyc_datas_path(@kyc_data.investor_kyc), notice: "Kyc Data was successfully created." }
      else
        format.html { redirect_to compare_ckyc_kra_kyc_datas_path, status: :unprocessable_entity }
        format.json { render json: @kyc_data.errors, status: :unprocessable_entity }
      end
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_kyc_data
    @kyc_data = KycData.find(params[:id])
    authorize(@kyc_data)
  end

  # Only allow a list of trusted parameters through.
  def kyc_data_params
    params.require(:kyc_data).permit(:investor_kyc_id, :entity_id, :source, :response)
  end
end
