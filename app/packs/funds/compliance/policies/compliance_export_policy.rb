# ⑨ Register export: viewers; rows limited to funds the user can see (E47, X36).
class ComplianceExportPolicy < ComplianceBasePolicy
  def create?
    viewer?
  end
end
