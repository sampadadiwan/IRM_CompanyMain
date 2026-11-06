# ⑦ Maker–checker. Requesting needs editor rights on the target's fund; deciding needs approver rights.
# "Approver ≠ requester unless the only eligible user" is enforced in ComplianceRequestDecide (X18, X30, X57, X64).
class ComplianceRequestPolicy < ComplianceBasePolicy
  def show?
    viewer? && same_firm? && target_visible?
  end

  def create?
    editor? && same_firm? && target_visible?
  end

  def approve?
    approver? && same_firm? && target_visible?
  end

  def reject?
    approve?
  end

  private

  def target_visible?
    fp = record.fund_compliance_pack
    fp.present? && fund_visible?(fp.fund)
  end
end
