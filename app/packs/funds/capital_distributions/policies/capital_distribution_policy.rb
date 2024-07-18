class CapitalDistributionPolicy < FundBasePolicy
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

  def update?
    permissioned_employee?(:update)
  end

  def payments_completed?
    update?
  end

  def mark_payments_completed?
    update? 
  end

  def approve?
    !record.approved && create?
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
