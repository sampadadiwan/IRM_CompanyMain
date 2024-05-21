class InvestorKycSebiDatasController < ApplicationController
  before_action :set_investor_kyc_sebi_data, only: %i[show edit update destroy]
  skip_after_action :verify_authorized, only: %i[sub_categories]

  # GET /investor_kyc_sebi_datas or /investor_kyc_sebi_datas.json
  def index
    @investor_kyc_sebi_datas = policy_scope(InvestorKycSebiData).includes(:investor)
    authorize(InvestorKycSebiData)

    @investor_kyc_sebi_datas = InvestorKycSebiData.where(investor_id: params[:investor_id]) if params[:investor_id].present?
  end

  # GET /investor_kyc_sebi_datas/1 or /investor_kyc_sebi_datas/1.json
  def show; end

  # GET /investor_kyc_sebi_datas/new
  def new
    @investor_kyc_sebi_data = InvestorKycSebiData.new(investor_kyc_sebi_data_params)
    authorize(@investor_kyc_sebi_data)
  end

  # GET /investor_kyc_sebi_datas/1/edit
  def edit; end

  # POST /investor_kyc_sebi_datas or /investor_kyc_sebi_datas.json
  def create
    @investor_kyc_sebi_data = InvestorKycSebiData.new(investor_kyc_sebi_data_params)

    respond_to do |format|
      if @investor_kyc_sebi_data.save
        format.html { redirect_to investor_kyc_sebi_data_url(@investor_kyc_sebi_data), notice: "Investor sebi info was successfully created." }
        format.json { render :show, status: :created, location: @investor_kyc_sebi_data }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @investor_kyc_sebi_data.errors, status: :unprocessable_entity }
      end
    end
  end

  def sub_categories
    @sub_categories = InvestorKycSebiData::INVESTOR_SUB_CATEGORIES.stringify_keys[params[:investor_category]] || []
  end

  # PATCH/PUT /investor_kyc_sebi_datas/1 or /investor_kyc_sebi_datas/1.json
  def update
    respond_to do |format|
      if @investor_kyc_sebi_data.update(investor_kyc_sebi_data_params)
        format.html { redirect_to investor_kyc_sebi_data_url(@investor_kyc_sebi_data), notice: "Investor sebi info was successfully updated." }
        format.json { render :show, status: :ok, location: @investor_kyc_sebi_data }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @investor_kyc_sebi_data.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /investor_kyc_sebi_datas/1 or /investor_kyc_sebi_datas/1.json
  def destroy
    @investor_kyc_sebi_data.destroy!

    respond_to do |format|
      format.html { redirect_to investor_kyc_sebi_datas_url, notice: "Investor sebi info was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_investor_kyc_sebi_data
    @investor_kyc_sebi_data = InvestorKycSebiData.find(params[:id])
    authorize(@investor_kyc_sebi_data)
  end

  # Only allow a list of trusted parameters through.
  def investor_kyc_sebi_data_params
    params.require(:investor_kyc_sebi_data).permit(:investor_id, :entity_id, :fund_id, :investor_category, :investor_sub_category)
  end
end
