# ⑥ Manual duties: list and mark done with a note and evidence (H27, X33, X37, E43).
class ComplianceDutiesController < ApplicationController
  def index
    authorize :compliance_home, :index?
    fund_pack_ids = policy_scope(FundCompliancePack).select(:id)
    @duties = ComplianceDuty.where(entity_id: current_user.entity_id, fund_compliance_pack_id: fund_pack_ids)
                            .includes(fund_compliance_pack: %i[fund compliance_pack]).order(:due_on)
  end

  def complete
    fund_pack_ids = policy_scope(FundCompliancePack).select(:id)
    duty = ComplianceDuty.where(entity_id: current_user.entity_id, fund_compliance_pack_id: fund_pack_ids).find_by(id: params[:id]) || raise(Pundit::NotAuthorizedError)
    authorize duty
    result = ComplianceDutyComplete.call(duty:, user: current_user, note: params[:note], evidence: params[:evidence])
    redirect_back_or_to(compliance_duties_path, **(result.success? ? { notice: "Duty done" } : { alert: result.error }))
  end
end
