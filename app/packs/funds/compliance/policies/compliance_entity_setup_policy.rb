# ② Setup screens: viewers read, editors change (X19); own firm only (X21).
class ComplianceEntitySetupPolicy < ComplianceBasePolicy
  def show?
    viewer? && same_firm?
  end

  def update?
    editor? && same_firm?
  end
end
