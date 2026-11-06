# ⑥ Register: viewers read items of funds they can see (X20); editors assign and explain.
class ComplianceRegisterItemPolicy < ComplianceBasePolicy
  def index?
    viewer?
  end

  def show?
    viewer? && fund_scoped_visible?
  end

  def assign?
    editor? && fund_scoped_visible?
  end

  def explain?
    assign?
  end
end
