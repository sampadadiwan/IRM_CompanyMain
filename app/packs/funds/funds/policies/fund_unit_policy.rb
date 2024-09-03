class FundUnitPolicy < FundBasePolicy
  def index?
    user.enable_funds
  end

  def show?
    permissioned_employee? ||
      permissioned_investor?
  end

  def create?
    permissioned_employee?(:create)
  end

  def new?
    create?
  end

  def verify?
    update?
  end

  def update?
    permissioned_employee?(:update)
  end

  def edit?
    update?
  end

  def generate_docs?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end
end
