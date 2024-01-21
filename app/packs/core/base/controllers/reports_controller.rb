class ReportsController < ApplicationController
  before_action :set_report, only: %i[show edit update destroy]

  # GET /reports or /reports.json
  def index
    @reports = policy_scope(Report)
    @reports = @reports.where(category: params[:category]) if params[:category].present?
  end

  # GET /reports/1 or /reports/1.json
  def show; end

  # GET /reports/new
  def new
    @report = Report.new
    @report.user = current_user
    @report.entity = current_user.entity
    @report.url = URI(request.referer).request_uri

    @report.name = ""
    hash = Rack::Utils.parse_query URI(request.referer).query
    hash.each_key do |k|
      @report.name += "#{hash[k]} " if k.include?("value")
    end
    authorize @report
  end

  # GET /reports/1/edit
  def edit; end

  # POST /reports or /reports.json
  def create
    @report = Report.new(report_params)
    @report.user = current_user
    @report.entity = current_user.entity
    authorize @report

    respond_to do |format|
      if @report.save
        format.html { redirect_to report_url(@report), notice: "Report was successfully created." }
        format.json { render :show, status: :created, location: @report }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @report.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /reports/1 or /reports/1.json
  def update
    respond_to do |format|
      if @report.update(report_params)
        format.html { redirect_to report_url(@report), notice: "Report was successfully updated." }
        format.json { render :show, status: :ok, location: @report }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @report.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /reports/1 or /reports/1.json
  def destroy
    @report.destroy!

    respond_to do |format|
      format.html { redirect_to reports_url, notice: "Report was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_report
    @report = Report.find(params[:id])
    authorize @report
    @bread_crumbs = { Reports: reports_path, "#{@report.name}": report_path(@report) }
  end

  # Only allow a list of trusted parameters through.
  def report_params
    params.require(:report).permit(:entity_id, :user_id, :name, :description, :url, :category)
  end
end
