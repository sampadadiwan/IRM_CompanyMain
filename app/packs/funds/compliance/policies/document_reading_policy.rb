# ⑦ Facts to confirm (design › Security item 1, LLD › DocumentFactPolicy): who may see a document's
# facts and who may confirm, correct, enter them or ask to read now.
#   see     — a compliance viewer of the same firm who can see the document itself (DocumentPolicy#show?)
#   confirm — the same, and a compliance editor (X48: viewers are refused, button and direct request)
# Investors and advisors are never compliance viewers (X22).
# Worked examples X48 — openspec/changes/fund-compliance-monitoring/business-rules.md
class DocumentReadingPolicy < ComplianceBasePolicy
  def index?
    viewer?
  end

  def show?
    viewer? && same_firm? && document_visible?
  end

  def confirm?
    editor? && same_firm? && document_visible?
  end

  def read_now?
    confirm?
  end

  def manual?
    confirm?
  end

  private

  def document_visible?
    record.document.present? && record.document.entity_id == user.entity_id && Pundit.policy(user, record.document).show?
  end
end
