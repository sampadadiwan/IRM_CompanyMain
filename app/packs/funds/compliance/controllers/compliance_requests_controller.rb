# ⑦ Maker–checker: create (editor), approve / reject (approver ≠ requester — X18, X30, X57, X64).
# Turbo stream: a request on a register item replaces that item's summary on its page and shows the
# flash; any other request shows the flash only. HTML falls back to a redirect (E140).
class ComplianceRequestsController < ApplicationController
  def create
    target = find_target
    raise Pundit::NotAuthorizedError if target.nil?

    probe = ComplianceRequest.new(entity_id: current_user.entity_id, target_type: target.class.name, target_id: target.id)
    authorize probe, :create?
    result = ComplianceRequestSubmit.call(user: current_user, kind: request_params[:kind], target:,
                                          reason: request_params[:reason], check_key: request_params[:check_key],
                                          payload: payload_params)
    respond_with_target(target, **(result.success? ? { notice: "Request sent for approval" } : { alert: result.error }))
  end

  def approve
    decide("approve")
  end

  def reject
    decide("reject")
  end

  private

  def decide(decision)
    request = policy_scope(ComplianceRequest).find_by(id: params[:id]) || raise(Pundit::NotAuthorizedError)
    authorize request, decision == "approve" ? :approve? : :reject?
    result = ComplianceRequestDecide.call(request:, decider: current_user, decision:, note: params[:note])
    respond_with_target(request.target, **(result.success? ? { notice: "Request #{request.reload.status}" } : { alert: result[:error] }))
  end

  def respond_with_target(target, notice: nil, alert: nil)
    respond_to do |format|
      format.turbo_stream do
        @notice = notice
        @alert = alert
        @item = target.is_a?(ComplianceRegisterItem) ? target.reload : nil
        render @item ? "compliance_register_items/updated" : "compliance_shared/flash"
      end
      format.html { redirect_back_or_to(compliance_home_path, notice:, alert:) }
    end
  end

  # Allow-listed target types only, loaded through the policy scope (never constantized from params)
  def find_target
    case request_params[:target_type]
    when "FundCompliancePack" then policy_scope(FundCompliancePack).find_by(id: request_params[:target_id])
    when "ComplianceRegisterItem" then policy_scope(ComplianceRegisterItem).find_by(id: request_params[:target_id])
    end
  end

  def request_params
    params.expect(compliance_request: %i[kind target_type target_id check_key reason])
  end

  # Only the payload keys each kind uses
  def payload_params
    raw = params.dig(:compliance_request, :payload)
    return {} if raw.blank?

    raw.permit(:limit, :version_id, :classification, :text).to_h
  end
end
