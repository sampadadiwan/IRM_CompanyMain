# ⑦ Creates a maker–checker request from an editor. Explanations move the item to Pending approval
# (E32); approvers are told (E46). Validation (reason length, lock rules, early adoption) lives on the model.
# Worked examples H14, E13, E17, E32, E46, X17, X52, X53, X56 — openspec/changes/fund-compliance-monitoring/business-rules.md
class ComplianceRequestSubmit
  Result = Struct.new(:request, :error, keyword_init: true) do
    def success?
      error.nil?
    end
  end

  def self.call(user:, kind:, target:, reason:, check_key: nil, payload: {})
    request = ComplianceRequest.new(entity_id: user.entity_id, kind:, target_type: target.class.name, target_id: target.id,
                                    check_key:, payload:, reason:, requested_by: user)
    return Result.new(request:, error: request.errors.full_messages.to_sentence) unless valid_target_state?(request, target)

    ActiveRecord::Base.transaction do
      request.save!
      target.update!(status: "pending_approval") if kind == "explanation"
    end
    ComplianceNotices.approval_requested(request)
    Result.new(request:)
  rescue ActiveRecord::RecordInvalid
    Result.new(request:, error: request.errors.full_messages.to_sentence)
  end

  # X32: explaining a closed item is refused
  def self.valid_target_state?(request, target)
    if request.kind == "explanation" && target.is_a?(ComplianceRegisterItem) && target.closed?
      request.errors.add(:base, "Item is closed")
      return false
    end
    request.valid?
  end
end
