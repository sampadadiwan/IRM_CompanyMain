class ReportsController < ApplicationController
  before_action :set_report, only: %i[show dynamic edit update destroy configure_grids]

  # GET /reports or /reports.json
  def index
    @reports = policy_scope(Report)
    @reports = @reports.where(category: params[:category]) if params[:category].present?
    @reports = @reports.where("tag_list like ?", "%#{params[:tag_list]}%") if params[:tag_list].present?
    @reports = @reports.where(id: params[:report_ids].split(",")) if params[:report_ids].present?
    @bread_crumbs = { Reports: reports_path, params[:tag_list] => "" }
  end

  # GET /reports/1 or /reports/1.json
  def show; end

  # This is a special kind of report which has dynamic URL to allow params to be passed to a report
  def dynamic
    @report_url = report.url_from(params)
    redirect_to @report_url.to_s
  end

  def prompt
    authorize Report
    model_class = params[:model_class].constantize
    query = params[:query]
    @report_url = ReportPrompt.generate_report_url(query, model_class)
    redirect_to @report_url.to_s
  end

  # GET /reports/new
  def new
    @report = Report.new
    @report.user = current_user
    @report.curr_role = current_user.curr_role
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
  def edit
    @report.decode_url
  end

  # POST /reports or /reports.json
  def create
    @report = Report.new(report_params)
    @report.user = current_user
    @report.curr_role = current_user.curr_role
    @report.entity = current_user.entity
    @report.decode_url

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
    @report.curr_role = current_user.curr_role
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

  def configure_grids
    model_class = @report.model.constantize
    @field_options = model_class::STANDARD_COLUMNS
    form_type = FormType.find_by(entity_id: current_user.entity_id, name: model_class.to_s)
    @custom_field_names = form_type.form_custom_fields.where.not(field_type: "GridColumns").pluck(:name).map(&:to_s) if form_type.present?
    @field_options = (@field_options.map { |name, value| [name, value] } + Array(@custom_field_names).map { |name| [name.humanize, "custom_fields.#{name}"] }).to_h
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
    params.require(:report).permit(:entity_id, :user_id, :name, :description, :url, :category, :tag_list, :curr_role, :metadata, :template_xls)
  end
end
