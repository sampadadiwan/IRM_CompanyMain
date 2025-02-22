class PortfolioReportsController < ApplicationController
  before_action :set_portfolio_report, only: %i[show edit update destroy]

  # GET /portfolio_reports
  def index
    @q = PortfolioReport.ransack(params[:q])
    @portfolio_reports = policy_scope(@q.result)
  end

  # GET /portfolio_reports/1
  def show; end

  # GET /portfolio_reports/new
  def new
    @portfolio_report = PortfolioReport.new
    @portfolio_report.entity_id = current_user.entity_id
    @portfolio_report.portfolio_report_sections.build
    authorize @portfolio_report
  end

  # GET /portfolio_reports/1/edit
  def edit; end

  # POST /portfolio_reports
  def create
    @portfolio_report = PortfolioReport.new(portfolio_report_params)
    authorize @portfolio_report
    if @portfolio_report.save
      redirect_to @portfolio_report, notice: "Portfolio report was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /portfolio_reports/1
  def update
    if @portfolio_report.update(portfolio_report_params)
      redirect_to @portfolio_report, notice: "Portfolio report was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /portfolio_reports/1
  def destroy
    @portfolio_report.destroy!
    redirect_to portfolio_reports_url, notice: "Portfolio report was successfully destroyed.", status: :see_other
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_portfolio_report
    @portfolio_report = PortfolioReport.find(params[:id])
    authorize @portfolio_report
  end

  # Only allow a list of trusted parameters through.
  def portfolio_report_params
    params.require(:portfolio_report).permit(:entity_id, :name, :tags, :include_kpi, :include_portfolio_investments, portfolio_report_sections_attributes: %i[id name data _destroy])
  end
end
