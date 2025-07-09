class CapitalCallPolicy < FundBasePolicy
  def index?
    user.enable_funds
  end

  def create?
    permissioned_employee?(:create)
  end

  def show?
    permissioned_employee?
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update)
  end

  def approve?
    !record.approved && update? && user.has_cached_role?(:approver)
  end

  def edit?
    update?
  end

  def recompute_fees?
    update?
  end

  def generate_docs?
    update?
  end

  def allocate_units?
    record.approved && record.unit_prices.present? && update?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end

  def reminder?
    update?
  end
end
