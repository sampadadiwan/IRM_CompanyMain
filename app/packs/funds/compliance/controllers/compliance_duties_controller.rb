# ⑥ Manual duties: the standard grid (filter, search, pages) and Mark done with a note and evidence
# (H27, X33, X37, E43). Mark done opens in the app's remote modal and answers with a Turbo stream that
# replaces the row, refreshes the stats cards and shows the flash.
class ComplianceDutiesController < ApplicationController
  include ComplianceCrumbs

  before_action :set_duty, only: %i[mark_done complete]

  def index
    authorize :compliance_home, :index?
    @q = ComplianceDuty.ransack(params[:q])
    scope = @q.result.where(entity_id: current_user.entity_id, fund_compliance_pack_id: fund_pack_ids)
              .includes(:owner, fund_compliance_pack: %i[fund compliance_pack compliance_pack_version])
    scope = search(scope, params.dig(:search, :value))
    @stats_scope = ComplianceDuty.where(id: scope.select(:id))
    scope = scope.order(:due_on, :id) if params.dig(:q, :s).blank?
    @pagy, @duties = pagy(scope, limit: params[:per_page] || 10)
    compliance_crumbs(["Duties", nil])
    respond_to do |format|
      format.html
      format.turbo_stream { render partial: "compliance_duties/index", locals: { duties: @duties } }
    end
  end

  # The Mark done form, drawn in the remote modal
  def mark_done
    authorize @duty, :complete?
  end

  def complete
    authorize @duty
    result = ComplianceDutyComplete.call(duty: @duty, user: current_user, note: params[:note], evidence: params[:evidence])
    notice, alert = result.success? ? ["Duty done", nil] : [nil, result.error]
    respond_to do |format|
      format.turbo_stream do
        @notice = notice
        @alert = alert
        @stats_scope = ComplianceDuty.where(entity_id: current_user.entity_id, fund_compliance_pack_id: fund_pack_ids)
        render "compliance_duties/complete"
      end
      format.html { redirect_back_or_to(compliance_duties_path, notice:, alert:) }
    end
  end

  private

  def fund_pack_ids
    policy_scope(FundCompliancePack).select(:id)
  end

  def set_duty
    @duty = ComplianceDuty.where(entity_id: current_user.entity_id, fund_compliance_pack_id: fund_pack_ids).find_by(id: params[:id]) ||
            raise(Pundit::NotAuthorizedError)
  end

  # Search box: duty or period
  def search(scope, value)
    return scope if value.blank?

    like = "%#{ActiveRecord::Base.sanitize_sql_like(value.to_s.strip)}%"
    scope.where("compliance_duties.duty_key LIKE :like OR compliance_duties.period_key LIKE :like", like:)
  end
end
