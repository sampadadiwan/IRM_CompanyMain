# Compliance home: every fund of the firm the user can see, with its packs, run health and open items.
# A fund with no pack is listed under "Not monitored" so it is never mistaken for compliant (E10).
class ComplianceHomeController < ApplicationController
  include ComplianceCrumbs

  def index
    authorize :compliance_home, :index?
    @setup = ComplianceEntitySetup.for(current_user.entity)
    # ⑩ Timing banner: the firm's last successful run, and whether a later run failed (E185)
    runs = ComplianceRun.where(entity_id: current_user.entity_id)
    @last_success = runs.where(status: "succeeded").order(:created_at, :id).last
    @failed_since = @last_success.present? && runs.where(status: "failed").exists?(["created_at > ?", @last_success.created_at])
    # R175 / E203: the one funds grid (ComplianceFundsGrid) — the standard grid filter (Fund ransack, its
    # own allowlisted attributes) and search by fund name narrow the rows, and the cards are their totals
    @q = Fund.where(id: ComplianceAccess.fund_ids(current_user)).ransack(params[:q])
    funds = @q.result.order(:name)
    term = params.dig(:search, :value).to_s.strip
    funds = funds.where("funds.name LIKE ?", "%#{Fund.sanitize_sql_like(term)}%") if term.present?
    @grid = ComplianceFundsGrid.new(funds, fund_packs: policy_scope(FundCompliancePack), items: policy_scope(ComplianceRegisterItem))
    # Search / filter inside the grid's own frame: just the cards and table
    return render(partial: "compliance_shared/funds_grid", locals: { grid: @grid }) if turbo_frame_request? && request.headers["Turbo-Frame"] == "compliance_funds_frame"

    compliance_crumbs
  end

  # ⑩ The Getting started frame on its own (refreshes in place; X90: viewers of the firm only)
  def getting_started
    authorize :compliance_home, :index?
    render partial: "compliance_shared/getting_started"
  end

  # E201: one step's popup, fetched by journey_step_info_controller.js when its circle is clicked (as on
  # every other journey — WorkflowInstancesController#step_info). The firm is always the user's own;
  # the key is matched against the fixed step list, never used to call anything (X95: unknown → 404).
  def getting_started_step
    authorize :compliance_home, :index?
    key = ComplianceGettingStarted::STEPS.find { |k| k == params[:key].to_s }
    return head(:not_found) unless key

    service = ComplianceGettingStarted.new(current_user.entity, current_user)
    step = service.call.steps.find { |s| s.key == key }
    render partial: "compliance_shared/getting_started_step",
           locals: { step:, details: service.details(key), setup: ComplianceEntitySetup.for(current_user.entity) }
  end

  # E202: remember the panel's minimise toggle for this user, in their own preferences
  # (users.preferences["compliance"]["getting_started_collapsed"]) — no schema change. Only a boolean is
  # read from params; the rest of the user's preferences are kept as they are.
  def getting_started_collapse
    authorize :compliance_home, :index?
    prefs = (current_user.preferences.is_a?(Hash) ? current_user.preferences : {}).deep_dup
    prefs["compliance"] = (prefs["compliance"] || {}).merge("getting_started_collapsed" => params[:collapsed].to_s == "true")
    # update_column: a UI preference, not a profile edit — no validations, callbacks or audit noise
    current_user.update_column(:preferences, prefs)
    head :no_content
  end
end
