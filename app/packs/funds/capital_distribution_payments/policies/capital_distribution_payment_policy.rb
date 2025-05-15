class CapitalDistributionPaymentPolicy < FundBasePolicy
  def index?
    user.enable_funds
  end

  def show?
    permissioned_employee? ||
      permissioned_investor?
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

  def preview?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end

  def reminder?
    update?
  end
end
