# ⑦ Marking a scan "Signed (wet ink)": a compliance editor who can see the document (X27).
class DocumentSignoffPolicy < ComplianceBasePolicy
  def create?
    editor? && record.document.present? && record.document.entity_id == user.entity_id &&
      Pundit.policy(user, record.document).show?
  end
end
