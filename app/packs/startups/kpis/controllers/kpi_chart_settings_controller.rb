class KpiChartSettingsController < ApplicationController
  def index
    @kpi_chart_settings = policy_scope(KpiChartSetting)
    @kpi_chart_settings = @kpi_chart_settings.where(entity_id: params[:entity_id]) if params[:entity_id].present?
    @kpi_chart_settings = @kpi_chart_settings.where(portfolio_company_id: params[:portfolio_company_id]) if params[:portfolio_company_id].present?

    render json: @kpi_chart_settings
  end

  def show
    @kpi_chart_setting = KpiChartSetting.find(params[:id])
    authorize @kpi_chart_setting
    render json: @kpi_chart_setting
  end

  def create
    @kpi_chart_setting = KpiChartSetting.find_by(
      name: kpi_chart_setting_params[:name],
      user_id: current_user.id,
      entity_id: kpi_chart_setting_params[:entity_id] || current_user.entity_id,
      portfolio_company_id: kpi_chart_setting_params[:portfolio_company_id]
    ) || KpiChartSetting.new(
      name: kpi_chart_setting_params[:name],
      user_id: current_user.id,
      entity_id: kpi_chart_setting_params[:entity_id] || current_user.entity_id,
      portfolio_company_id: kpi_chart_setting_params[:portfolio_company_id]
    )

    authorize @kpi_chart_setting
    @kpi_chart_setting.config = kpi_chart_setting_params[:config]
    @kpi_chart_setting.is_default = kpi_chart_setting_params[:is_default] if kpi_chart_setting_params.key?(:is_default)

    if @kpi_chart_setting.save
      render json: @kpi_chart_setting, status: :created
    else
      render json: { errors: @kpi_chart_setting.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @kpi_chart_setting = KpiChartSetting.find(params[:id])
    authorize @kpi_chart_setting
    @kpi_chart_setting.destroy
    head :no_content
  end

  private

  def kpi_chart_setting_params
    params.require(:kpi_chart_setting).permit(:name, :entity_id, :portfolio_company_id, :is_default, config: %i[name type])
  end
end
