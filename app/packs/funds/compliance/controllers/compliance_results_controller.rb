# ⑤ One stored result with its working and the setup of its day (H18). Results are never deleted (X66).
class ComplianceResultsController < ApplicationController
  before_action :set_result

  def show
    authorize @result
    @setup_then = ComplianceSetupAsOf.call(@result)
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
