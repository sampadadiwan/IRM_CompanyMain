class FundUnitSettingsController < ApplicationController
  include FundsHelper

  before_action :set_fund_unit_setting, only: %i[show edit update destroy]

  # GET /fund_unit_settings or /fund_unit_settings.json
  def index
    @q = FundUnitSetting.ransack(params[:q])

    @fund_unit_settings = policy_scope(@q.result)
    @fund_unit_settings = @fund_unit_settings.where(fund_id: params[:fund_id]) if params[:fund_id]
    @fund_unit_settings = @fund_unit_settings.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?
    @pagy, @fund_unit_settings = pagy(@fund_unit_settings, limit: params[:per_page] || 10) if params[:all].blank?
    respond_to do |format|
      format.html
      format.turbo_stream { render partial: 'fund_unit_settings/index', locals: { fund_unit_settings: @fund_unit_settings } }
      format.xlsx
    end
    fund_bread_crumbs("Unit Settings")
  end

  # GET /fund_unit_settings/1 or /fund_unit_settings/1.json
  def show; end

  # GET /fund_unit_settings/new
  def new
    @fund_unit_setting = FundUnitSetting.new(fund_unit_setting_params)
    authorize @fund_unit_setting
    setup_custom_fields(@fund_unit_setting)
  end

  # GET /fund_unit_settings/1/edit
  def edit
    setup_custom_fields(@fund_unit_setting)
  end

  # POST /fund_unit_settings or /fund_unit_settings.json
  def create
    @fund_unit_setting = FundUnitSetting.new(fund_unit_setting_params)
    authorize @fund_unit_setting

    respond_to do |format|
      if @fund_unit_setting.save
        format.html { redirect_to fund_unit_setting_url(@fund_unit_setting), notice: "Fund unit setting was successfully created." }
        format.json { render :show, status: :created, location: @fund_unit_setting }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @fund_unit_setting.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /fund_unit_settings/1 or /fund_unit_settings/1.json
  def update
    respond_to do |format|
      if @fund_unit_setting.update(fund_unit_setting_params)
        format.html { redirect_to fund_unit_setting_url(@fund_unit_setting), notice: "Fund unit setting was successfully updated." }
        format.json { render :show, status: :ok, location: @fund_unit_setting }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @fund_unit_setting.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /fund_unit_settings/1 or /fund_unit_settings/1.json
  def destroy
    @fund_unit_setting.destroy

    respond_to do |format|
      format.html { redirect_to fund_unit_settings_url, notice: "Fund unit setting was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_fund_unit_setting
    @fund_unit_setting = FundUnitSetting.find(params[:id])
    authorize @fund_unit_setting
    @bread_crumbs = { Funds: funds_path, "#{@fund_unit_setting.fund.name}": fund_path(@fund_unit_setting.fund),
                      'Fund Unit Settings': fund_unit_settings_path(fund_id: @fund_unit_setting.fund_id),
                      "#{@fund_unit_setting}": nil }
  end

  # Only allow a list of trusted parameters through.
  def fund_unit_setting_params
    params.require(:fund_unit_setting).permit(:entity_id, :fund_id, :name, :management_fee, :setup_fee, :carry, :form_type_id, :isin, :gp_units, properties: {})
  end
end
