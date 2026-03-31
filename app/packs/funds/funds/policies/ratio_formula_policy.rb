class RatioFormulaPolicy < FundBasePolicy
  def index?
    user.enable_funds
  end

  def show?
    index?
  end

  def create?
    user.enable_funds && permissioned_employee?(:create)
  end

  def new?
    create?
  end

  def update?
    user.enable_funds && permissioned_employee?(:update)
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
