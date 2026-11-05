# ⑥ Manual duties: editors mark done (X34 — viewers refused).
class ComplianceDutyPolicy < ComplianceBasePolicy
  def show?
    viewer? && same_firm? && fund_visible?(record.fund_compliance_pack.fund)
  end

  def complete?
    editor? && same_firm? && fund_visible?(record.fund_compliance_pack.fund)
  end
end
