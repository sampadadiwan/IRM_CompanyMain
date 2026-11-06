# ① Draft edits, test runs (preview) and publishing. Locked CapHive packs are never customer-writable
# (X13, X55); a preview never writes results (R37, H48, E89).
class CompliancePackVersionPolicy < ComplianceBasePolicy
  def show?
    Pundit.policy(user, record.compliance_pack).show?
  end

  def update?
    record.draft? && Pundit.policy(user, record.compliance_pack).update?
  end

  def publish?
    update?
  end

  def test_run?
    update?
  end
end
