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
    @funds = Fund.where(id: ComplianceAccess.fund_ids(current_user)).order(:name)
    @fund_packs = policy_scope(FundCompliancePack).active.includes(:compliance_pack, :compliance_pack_version).group_by(&:fund_id)
    items = policy_scope(ComplianceRegisterItem).open_items
    @open_counts = items.group(:fund_id).count
    # Stats cards (SQL counts): latest result per check of every visible attached pack, as each fund's
    # Compliance tab shows them (R42: highest id, superseded ignored)
    fp_ids = @fund_packs.values.flatten.map(&:id)
    latest_ids = ComplianceResult.where(fund_compliance_pack_id: fp_ids, superseded_reason: nil)
                                 .group(:fund_compliance_pack_id, :check_key).maximum(:id).values
    outcomes = ComplianceResult.where(id: latest_ids).group(:outcome).count
    monitored = @funds.select { |f| @fund_packs[f.id].present? }
    @stats = {
      monitored: monitored.size,
      breach: outcomes["breach"].to_i,
      needs_review: outcomes["needs_review"].to_i,
      could_not_check: outcomes["could_not_check"].to_i,
      overdue: items.where(fix_by: ...Time.zone.today).count,
      stale: monitored.count { |f| ComplianceRun.stale?(f) }
    }
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
