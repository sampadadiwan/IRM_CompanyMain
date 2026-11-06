# ⑤ Results are append-only: readable by viewers of the fund; never deleted, never re-run for a past date (X65, X66).
class ComplianceResultPolicy < ComplianceBasePolicy
  def show?
    viewer? && same_firm? && fund_visible?(record.fund_compliance_pack.fund)
  end

  def destroy?
    false
  end

  def rerun?
    false
  end
end
