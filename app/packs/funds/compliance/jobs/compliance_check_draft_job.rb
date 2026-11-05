# ⑧ Drafts a check from a sentence in the background (AI only in jobs — LLD › External Integrations).
# Idempotent: a draft that is no longer "drafting" (ready, saved, failed) is left alone on retry.
# Worked examples H37, X42 — openspec/changes/fund-compliance-monitoring/business-rules.md
class ComplianceCheckDraftJob < ApplicationJob
  queue_as :default

  def perform(draft_id)
    # Reload through the draft's own entity; nothing from the job arguments beyond the id is trusted
    draft = ComplianceCheckDraft.find_by(id: draft_id)
    return if draft.nil? || draft.status != "drafting"

    ComplianceCheckDrafter.call(draft:)
  end
end
