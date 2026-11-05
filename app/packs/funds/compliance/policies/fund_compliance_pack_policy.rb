# ② Attaching packs, Run now, previews. Editors only, on funds of their own firm they can see (X19, X20, X23).
class FundCompliancePackPolicy < ComplianceBasePolicy
  def index?
    viewer?
  end

  def show?
    viewer? && fund_scoped_visible?
  end

  def create?
    editor? && fund_scoped_visible? && record.compliance_pack.present? &&
      (record.compliance_pack.entity_id.nil? || record.compliance_pack.entity_id == user.entity_id)
  end

  def run_now?
    editor? && fund_scoped_visible?
  end

  def preview?
    show?
  end

  def request_change?
    editor? && fund_scoped_visible?
  end
end
