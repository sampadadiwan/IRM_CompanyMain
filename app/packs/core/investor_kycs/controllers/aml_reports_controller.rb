class AmlReportsController < ApplicationController
  before_action :set_aml_report, only: %i[show toggle_approved]
  after_action :verify_authorized, except: %i[index search show]

  # GET /aml_reports or /aml_reports.json
  def index
    @aml_reports = policy_scope(AmlReport)
    authorize(AmlReport)
    @aml_reports = @aml_reports.where(id: search_ids) if params[:search] && params[:search][:value].present?
    @aml_reports = @aml_reports.where(investor_kyc_id: params[:investor_kyc_id]) if params[:investor_kyc_id]

    @aml_reports = @aml_reports.where(match_status: params[:match_status]) if params[:match_status].present?
    @aml_reports = @aml_reports.page(params[:page]) if params[:all].blank?

    respond_to do |format|
      format.html
      format.turbo_stream
      format.json { render json: AmlReportDatatable.new(params, aml_reports: @aml_reports) }
    end
  end

  def search_ids
    query = "#{params[:search][:value]}*"
    entity_ids = [current_user.entity_id]
    @aml_reports = AmlReportIndex.filter(terms: { entity_id: entity_ids })
                                 .query(query_string: { fields: AmlReportIndex::SEARCH_FIELDS,
                                                        query:, default_operator: 'and' }).map(&:id)
  end

  # GET /aml_reports/1 or /aml_reports/1.json or /aml_reports/1.pdf
  def show
    authorize @aml_report
    respond_to do |format|
      format.html { render "show" }
      format.json { render json: @aml_report }
    end
  end

  def toggle_approved
    approved_by_id = @aml_report.approved ? nil : current_user.id
    respond_to do |format|
      if @aml_report.update(approved: !@aml_report.approved, approved_by_id:)
        format.html { redirect_to aml_report_url(@aml_report), notice: "Aml Report status was successfully updated." }
        format.json { render :show, status: :ok, location: @aml_report }
      else
        # no edit view
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @aml_report.errors, status: :unprocessable_entity }
      end
    end
  end

  def generate_new
    @aml_report = AmlReport.new(aml_report_params)
    authorize(@aml_report)
    @aml_report.generate
    respond_to do |format|
      if @aml_report.save
        format.html { redirect_to investor_kyc_url(@aml_report.investor_kyc), notice: "Aml Report was successfully created." }
        format.json { render :show, status: :created, location: @aml_report }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @aml_report.errors, status: :unprocessable_entity }
      end
    end
  end

  # POST /aml_reports or /aml_reports.json
  def create; end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_aml_report
    @aml_report = AmlReport.find(params[:id])
    authorize(@aml_report)
  end

  # Only allow a list of trusted parameters through.
  def aml_report_params
    params.require(:aml_report).permit(:investor_id, :investor_kyc_id, :entity_id, :name, :options)
  end
end
