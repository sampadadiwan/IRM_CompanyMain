# ⑥ Manual duties: the standard grid (filter, search, pages) and Mark done with a note and evidence
# (H27, X33, X37, E43). Mark done opens in the app's remote modal and answers with a Turbo stream that
# replaces the row, refreshes the stats cards and shows the flash.
class ComplianceDutiesController < ApplicationController
  include ComplianceCrumbs

  before_action :set_duty, only: %i[mark_done complete]

  def index
    authorize :compliance_home, :index?
    scope = filtered_scope(params[:q], params.dig(:search, :value))
            .includes(:owner, fund_compliance_pack: %i[fund compliance_pack compliance_pack_version])
    @stats_scope = ComplianceDuty.where(id: scope.select(:id))
    scope = scope.order(:due_on, :id) if params.dig(:q, :s).blank?
    @pagy, @duties = pagy(scope, limit: params[:per_page] || 10)
    compliance_crumbs(["Duties", nil])
    # The Compliance hub's lazy Duties pane (R170): this page's content inside the hub frame
    return render_hub_pane(:duties, "compliance_duties/index") if hub_frame_request?(:duties)

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
        # E198 / R163: the cards follow the grid's own filter and search, carried by the Mark done form
        @stats_scope = ComplianceDuty.where(id: filtered_scope(grid_query, params[:grid_search]).select(:id))
        render "compliance_duties/complete"
      end
      format.html { redirect_back_or_to(compliance_duties_path, notice:, alert:) }
    end
  end

  private

  def fund_pack_ids
    policy_scope(FundCompliancePack).select(:id)
  end

  # The grid's ransack filter, sent back by the Mark done form as JSON; anything unreadable means "no filter"
  def grid_query
    value = params[:grid_q].present? ? JSON.parse(params[:grid_q]) : nil
    value.is_a?(Hash) ? value : nil
  rescue JSON::ParserError
    nil
  end

  # The grid's rows: ransack filter (allow-listed attributes only) + search box, inside the user's funds
  def filtered_scope(query, search_value)
    @q = ComplianceDuty.ransack(query)
    search(@q.result.where(entity_id: current_user.entity_id, fund_compliance_pack_id: fund_pack_ids), search_value)
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
