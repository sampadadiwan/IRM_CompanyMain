class ReportInsightsController < ApplicationController
  before_action :set_report_insight, only: %i[show]
  after_action :verify_authorized, except: %i[index]
  after_action :verify_policy_scoped, only: %i[index]

  # GET /reports or /reports.json
  def index
    @report_insights = policy_scope(ReportInsight).includes(:report).includes(:triggered_by_user).order(created_at: :desc)
    @report_insights = filter_params(@report_insights, :report_id)
    @bread_crumbs = { Reports: reports_path, Analyses: nil }
    if params[:report_id].present?
      @report = Report.find(params[:report_id])
      authorize(@report, :show?)
      @bread_crumbs = { Reports: reports_path, "#{@report.name}": report_path(@report), 'Report Analyses': report_insights_path(report_id: @report.id) }
    end
  end

  # GET /reports/1 or /reports/1.json
  def show
    params[:report_id] = @report_insight.report_id
  end

  private

  def set_report_insight
    @report_insight = ReportInsight.includes(:report).find(params[:id])
    authorize @report_insight
    @bread_crumbs = { Reports: reports_path, "#{@report_insight.report.name}": report_path(@report_insight.report), 'AI Analysis': report_insight_path(@report_insight) }
  end
end
