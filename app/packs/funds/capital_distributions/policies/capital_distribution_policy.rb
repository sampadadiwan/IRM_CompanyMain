class CapitalDistributionPolicy < FundBasePolicy
  def index?
    user.enable_funds
  end

  def show?
    permissioned_employee?
  end

  def new?
    create?
  end

  def add_pis_to_capital_distribution?
    create?
  end

  def update?
    permissioned_employee?(:update)
  end

  def payments_completed?
    update?
  end

  def mark_payments_completed?
    update? && record.approved
  end

  def approve?
    !record.approved && update?
  end

  def redeem_units?
    record.unit_prices.present? && update?
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end

  def reminder?
    update?
  end
end
