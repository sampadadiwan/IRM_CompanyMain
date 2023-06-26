class CapitalRemittancePaymentPolicy < FundBasePolicy
  def index?
    true
  end

  def show?
    permissioned_employee? ||
      permissioned_investor?
  end

  def new?
    create?
  end

  def verify?
    update?
  end

  def update?
    permissioned_investor? ||
      permissioned_employee?(:update)
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end
end
