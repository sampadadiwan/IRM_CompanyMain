class FundUnitSettingPolicy < FundBasePolicy
  def index?
    user.enable_funds
  end

  def show?
    permissioned_employee?
  end

  def create?
    permissioned_employee?(:create)
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update)
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end
end
