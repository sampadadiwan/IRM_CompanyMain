# ⑥ Marks a duty done with a note and, when the duty requires it, evidence (X33, X37 — "Upload the evidence").
# Done after the due date is recorded as late (E43).
class ComplianceDutyComplete
  Result = Struct.new(:error, keyword_init: true) do
    def success?
      error.nil?
    end
  end

  def self.call(duty:, user:, note: nil, evidence: nil)
    return Result.new(error: "Already done") if duty.done?
    return Result.new(error: "Upload the evidence") if duty.evidence_required? && evidence.blank?

    ActiveRecord::Base.transaction do
      Document.create!(entity_id: duty.entity_id, owner: duty, folder: duty.document_folder, user:, name: "Evidence — #{duty.name}".truncate(100), file: evidence) if evidence.present?
      duty.update!(done_on: Time.zone.today, done_by: user, note:)
    end
    Result.new
  end
end
