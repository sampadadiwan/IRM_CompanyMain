class FundReportsController < ApplicationController
  before_action :set_fund_report, only: %i[edit update destroy regenerate download_page]

  # GET /fund_reports or /fund_reports.json
  def index
    @q = FundReport.ransack(params[:q])
    # Create the scope for the model
    @fund_reports = policy_scope(@q.result).includes(:fund).order(id: :desc)
    @fund_reports = @fund_reports.where(fund_id: params[:fund_id]) if params[:fund_id].present?
    @fund_reports = @fund_reports.where(name: params[:name]) if params[:name].present?
    if params[:fund_id].present?
      @fund = Fund.find(params[:fund_id])
      @bread_crumbs = { Funds: funds_path, "#{@fund.name}": fund_path(@fund), 'Fund Reports': nil }
    end
    if params[:all].blank?
      @fund_reports = @fund_reports.page(params[:page])
      @fund_reports = @fund_reports.per(params[:per_page].to_i) if params[:per_page].present?
    end

    respond_to do |format|
      format.html
      format.json
    end
  end

  # GET /fund_reports/1 or /fund_reports/1.json
  def show
    if params[:report].present? && params[:fund_id].present?
      @fund = Fund.find(params[:fund_id])
      doc = @fund.documents.where("documents.name LIKE ?", "#{params[:report].titleize}%").last
      if doc.present?
        authorize(doc)
        redirect_to document_path(doc)
      else
        fund_report = FundReport.new(fund_id: @fund.id, entity_id: @fund.entity_id)
        authorize(fund_report)
        name = params[:report].titleize.casecmp?("SEBI Report") ? "SEBI Report" : "CRISIL Report"
        FundReportJob.perform_later(@fund.entity_id, @fund.id, name, Time.zone.today - 3.months, Time.zone.today, current_user.id)
        redirect_to request.referer, notice: "#{name} generation started, please check back in a few mins"
      end
    else
      @fund_report = FundReport.find(params[:id])
      @bread_crumbs = { Funds: funds_path, "#{@fund_report.fund.name}": fund_path(@fund_report.fund), 'Fund Reports': fund_reports_path(fund_id: @fund_report.fund.id), "#{@fund_report.name.titleize}": fund_report_path(@fund_report, view: params[:view].to_s) }
      authorize @fund_report
    end
  end

  # GET /fund_reports/new
  def new
    @fund_report = FundReport.new
    @fund_report.fund_id = params[:fund_id]
    @fund_report.entity_id = current_user.entity_id
    @fund_report.start_date ||= Time.zone.today - 3.months
    @fund_report.end_date ||= Time.zone.today
    @bread_crumbs = { Funds: funds_path, "#{@fund_report.fund.name}": fund_path(@fund_report.fund), 'Fund Reports': fund_reports_path(fund_id: @fund_report.fund.id), New: nil }
    authorize @fund_report
  end

  # GET /fund_reports/1/edit
  def edit; end

  # POST /fund_reports or /fund_reports.json
  def create
    @fund_report = FundReport.new(fund_report_params)
    @fund_report.entity_id = @fund_report.fund.present? ? @fund_report.fund.entity_id : current_user.entity_id
    authorize @fund_report

    respond_to do |format|
      if FundReportJob.perform_later(@fund_report.entity_id, @fund_report.fund_id, @fund_report.name,
                                     @fund_report.start_date, @fund_report.end_date, current_user.id)

        format.html do
          if %w[sebireport crisilreport].include? @fund_report.name.downcase.delete("")
            # show notice and dont redirect
            redirect_to @fund_report.fund, notice: "Fund report will be generated, please check back in a few mins."
          else
            redirect_to fund_reports_url(fund_id: @fund_report.fund.id), notice: "Fund report will be generated, please check back in a few mins."
            format.json { render :show, status: :created, location: @fund_report }
          end
        end
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @fund_report.errors, status: :unprocessable_entity }
      end
    end
  end

  def regenerate
    if FundReportJob.perform_later(@fund_report.entity_id, @fund_report.fund_id, @fund_report.name,
                                   @fund_report.start_date, @fund_report.end_date, current_user.id)
      redirect_to fund_reports_url(fund_id: @fund_report.fund.id), notice: "Fund report will be regenerated, please check back in a few mins."
    else
      redirect_to fund_reports_url(fund_id: @fund_report.fund.id), alert: "Failed to regenerate fund report."
    end
  end

  def download_page
    single = params[:single].present? && params[:single] == "true"
    if FundReportJob.perform_later(@fund_report.entity_id, @fund_report.fund_id, @fund_report.name,
                                   @fund_report.start_date, @fund_report.end_date, current_user.id, excel: true, single:)
      redirect_to fund_reports_url(fund_id: @fund_report.fund.id), notice: "Fund report will be regenerated, please check back in a few mins."
    else
      redirect_to fund_reports_url(fund_id: @fund_report.fund.id), alert: "Failed to regenerate fund report."
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
    fund_id = @fund_report.fund_id
    @fund_report.destroy

    respond_to do |format|
      format.html { redirect_to fund_reports_url(fund_id:), notice: "Fund report was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_fund_report
    @fund_report = FundReport.find(params[:id])
    @bread_crumbs = { Funds: funds_path, "#{@fund_report.fund.name}": fund_path(@fund_report.fund), 'Fund Reports': fund_reports_path(fund_id: @fund_report.fund.id), "#{@fund_report.name.titleize}": fund_report_path(@fund_report, view: params[:view].to_s) }
    authorize @fund_report
  end

  # Only allow a list of trusted parameters through.
  def fund_report_params
    params.require(:fund_report).permit(:fund_id, :entity_id, :name, :name_of_scheme, :data, :start_date, :end_date)
  end
end
