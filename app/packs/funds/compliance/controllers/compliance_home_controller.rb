# Compliance home: every fund of the firm the user can see, with its packs, run health and open items.
# A fund with no pack is listed under "Not monitored" so it is never mistaken for compliant (E10).
class ComplianceHomeController < ApplicationController
  def index
    authorize :compliance_home, :index?
    @setup = ComplianceEntitySetup.for(current_user.entity)
    @funds = Fund.where(id: ComplianceAccess.fund_ids(current_user)).order(:name)
    @fund_packs = policy_scope(FundCompliancePack).active.includes(:compliance_pack, :compliance_pack_version).group_by(&:fund_id)
    @open_counts = policy_scope(ComplianceRegisterItem).open_items.group(:fund_id).count
  end
end
