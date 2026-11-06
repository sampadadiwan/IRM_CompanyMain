# ⑤ One stored result with its working and the setup of its day (H18). Results are never deleted (X66).
class ComplianceResultsController < ApplicationController
  include ComplianceCrumbs

  before_action :set_result

  def show
    authorize @result
    @setup_then = ComplianceSetupAsOf.call(@result)
    fp = @result.fund_compliance_pack
    compliance_fund_crumbs(fp.fund, [fp.pack_name, fund_compliance_pack_path(fp)],
                           [@result.working_hash["check_name"] || @result.check_key.humanize, nil])
  end

  def destroy
    authorize @result
  end

  private

  def set_result
    fund_pack_ids = policy_scope(FundCompliancePack).select(:id)
    @result = ComplianceResult.where(entity_id: current_user.entity_id, fund_compliance_pack_id: fund_pack_ids).find_by(id: params[:id]) || raise(Pundit::NotAuthorizedError)
  end
end
