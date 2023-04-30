class FundReportsController < ApplicationController
  before_action :set_fund_report, only: %i[show edit update destroy]

  # GET /fund_reports or /fund_reports.json
  def index
    @fund_reports = policy_scope(FundReport).includes(:fund)
    @fund_reports = @fund_reports.where(fund_id: params[:fund_id]) if params[:fund_id].present?
    @fund_reports = @fund_reports.where(name: params[:name]) if params[:name].present?

    respond_to do |format|
      format.html
      format.json { render json: FundReportDatatable.new(params, fund_reports: @fund_reports) }
    end
  end

  # GET /fund_reports/1 or /fund_reports/1.json
  def show; end

  # GET /fund_reports/new
  def new
    @fund_report = FundReport.new
    @fund_report.entity_id = current_user.entity_id
    @fund_report.start_date ||= Time.zone.today - 3.months
    @fund_report.end_date ||= Time.zone.today
    authorize @fund_report
  end

  # GET /fund_reports/1/edit
  def edit; end

  # POST /fund_reports or /fund_reports.json
  def create
    @fund_report = FundReport.new(fund_report_params)
    @fund_report.entity_id = current_user.entity_id
    authorize @fund_report

    respond_to do |format|
      if FundReportJob.perform_later(@fund_report.entity_id, @fund_report.fund_id, @fund_report.name,
                                     @fund_report.start_date, @fund_report.end_date, current_user.id)
        format.html { redirect_to fund_reports_url, notice: "Fund report will be generated, please check back in a few mins." }
        format.json { render :show, status: :created, location: @fund_report }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @fund_report.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /fund_reports/1 or /fund_reports/1.json
  def update
    respond_to do |format|
      if @fund_report.update(fund_report_params)
        format.html { redirect_to fund_report_url(@fund_report), notice: "Fund report was successfully updated." }
        format.json { render :show, status: :ok, location: @fund_report }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @fund_report.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /fund_reports/1 or /fund_reports/1.json
  def destroy
    @fund_report.destroy

    respond_to do |format|
      format.html { redirect_to fund_reports_url, notice: "Fund report was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_fund_report
    @fund_report = FundReport.find(params[:id])
    authorize @fund_report
  end

  # Only allow a list of trusted parameters through.
  def fund_report_params
    params.require(:fund_report).permit(:fund_id, :entity_id, :name, :name_of_scheme, :data, :start_date, :end_date)
  end
end
