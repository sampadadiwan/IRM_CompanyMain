# Compliance home: every fund of the firm the user can see, with its packs, run health and open items.
# A fund with no pack is listed under "Not monitored" so it is never mistaken for compliant (E10).
class ComplianceHomeController < ApplicationController
  include ComplianceCrumbs

  def index
    authorize :compliance_home, :index?
    @setup = ComplianceEntitySetup.for(current_user.entity)
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
end
