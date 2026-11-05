# ⑦ Decides a maker–checker request. The approver must be an eligible approver (Compliance approver or
# company admin) other than the requester — unless the entity has exactly one eligible user, who then
# self-approves and the request is labelled "Self-approved — single approver" (R11, E109, E111, X18, X30, X57, X64).
# The approved change is applied in the same transaction; a second decision changes nothing (X31).
# Worked examples H14, H15, H16, H26, H50, H55, H59, E12, E39 — openspec/changes/fund-compliance-monitoring/business-rules.md
class ComplianceRequestDecide < Trailblazer::Operation
  step :lock_pending
  step :check_decider
  step :apply
  step :notify
  left :report

  def lock_pending(ctx, request:, **)
    request.lock!
    return true if request.pending?

    ctx[:error] = "Already decided"
    false
  end

  def check_decider(ctx, request:, decider:, **)
    unless ComplianceAccess.approver?(decider) && decider.entity_id == request.entity_id
      ctx[:error] = "Only a Compliance approver can decide this request"
      return false
    end
    return true unless decider.id == request.requested_by_id

    # Single eligible user may approve their own request, labelled everywhere (E109)
    eligible = ComplianceAccess.eligible_approvers(request.entity)
    if eligible.size == 1 && eligible.first.id == decider.id
      ctx[:self_approved] = true
      return true
    end
    ctx[:error] = "Another approver must approve your request"
    false
  end

  def apply(ctx, request:, decider:, decision:, note: nil, **)
    ActiveRecord::Base.transaction do
      status = decision.to_s == "approve" ? "approved" : "rejected"
      request.update!(status:, decided_by: decider, decided_at: Time.current, decision_note: note,
                      self_approved: ctx[:self_approved] || false)
      status == "approved" ? approve_effects(request) : reject_effects(request)
    end
    true
  end

  def notify(_ctx, request:, **)
    ComplianceNotices.request_decided(request)
    true
  end

  def report(ctx, **)
    ctx[:error] ||= "Could not decide the request"
  end

  private

  def approve_effects(request)
    fp = request.fund_compliance_pack
    today = Time.zone.today
    case request.kind
    when "explanation"
      item = request.target
      item.update!(status: "explained", approved_figure: item.last_result&.figure, reopened_worse: false)
    when "disable"
      # H15: the check stops running; its open item closes "Check disabled"
      fp.compliance_register_items.open_items.where(check_key: request.check_key).find_each { |i| i.close!("disabled", on: today) }
    when "detach"
      # H16: open items close "Pack detached"; history stays readable
      fp.update!(status: "detached")
      fp.compliance_register_items.open_items.find_each { |i| i.close!("detached", on: today) }
    when "early_adoption"
      fp.update!(compliance_pack_version_id: request.payload_hash["version_id"])
    when "classification"
      fp.update!(classification: request.payload_hash["classification"])
    end
  end

  # E39: a rejected explanation returns the item to In progress; E12: a rejected override is discarded
  def reject_effects(request)
    return unless request.kind == "explanation"

    request.target.update!(status: "in_progress")
  end
end
