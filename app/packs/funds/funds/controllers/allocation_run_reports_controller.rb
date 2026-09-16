# The allocation run checker: runs the deterministic checks over one finished AllocationRun and
# shows the resulting report. See docs/modules/allocation/allocation_run_checker_requirements.md.
#
# There is one report per run — checking a run that has already been checked re-runs the checks
# and overwrites the previous result, so the badge on the allocation screen is never stale.
class AllocationRunReportsController < ApplicationController
  helper AllocationRunReportsHelper
  before_action :set_report, only: :show
  after_action :verify_authorized

  # GET /allocation_run_reports/:id
  def show
    authorize @report
    @allocation_run = @report.allocation_run
    @fund = @report.fund
    @tab = %w[summary run arithmetic].include?(params[:tab]) ? params[:tab] : "summary"
  end

  # POST /allocation_run_reports?allocation_run_id=…
  # Queues the checks and sends the person to the report page, which shows "Checking…" until
  # the job writes a result.
  def create
    allocation_run = AllocationRun.find(params[:allocation_run_id])
    @report = AllocationRunReport.find_or_initialize_by(allocation_run: allocation_run)
    @report.entity_id = allocation_run.entity_id
    @report.fund_id = allocation_run.fund_id
    authorize @report

    # A check for this run is already in flight — queuing another would race the running job
    # and whichever one finishes last would silently overwrite the other's result.
    if @report.persisted? && @report.pending?
      redirect_to allocation_run_report_path(@report), notice: "This allocation run is already being checked."
      return
    end

    @report.assign_attributes(
      user: current_user,
      status: "Pending",
      message: nil,
      checked_at: nil,
      json_fields: @report.json_fields_for_recheck
    )

    case save_report(allocation_run)
    when :saved
      AllocationRunReportJob.perform_later(@report.id)
      redirect_to allocation_run_report_path(@report), notice: "Checking this allocation run. The result appears here when it is done."
    when :already_running
      redirect_to allocation_run_report_path(@report), notice: "This allocation run is already being checked."
    else
      redirect_back_or_to(allocate_form_fund_path(allocation_run.fund), alert: @report.errors.full_messages.join(", "))
    end
  end

  private

  # There is a unique index on allocation_run_id, so two people pressing Check at the same
  # moment (or one double-click) both initialize a new record and the second insert raises
  # rather than returning false. Both of them want the same thing — a fresh check of this run —
  # but only the winner should queue a job; the loser just points at the row the winner made,
  # which is already Pending, so a duplicate job never gets queued for the same check.
  # @return [:saved, :already_running, false]
  def save_report(allocation_run)
    @report.save ? :saved : false
  rescue ActiveRecord::RecordNotUnique
    existing = AllocationRunReport.find_by(allocation_run: allocation_run)
    return false if existing.nil?

    @report = existing
    :already_running
  end

  def set_report
    @report = AllocationRunReport.find(params[:id])
  end
end
