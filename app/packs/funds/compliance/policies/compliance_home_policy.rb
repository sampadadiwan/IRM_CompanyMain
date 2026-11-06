# Compliance home page — viewers only (X22: investors never see Compliance).
class ComplianceHomePolicy < ComplianceBasePolicy
  def index?
    viewer?
  end
end
