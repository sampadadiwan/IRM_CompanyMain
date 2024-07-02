class CapitalCallPolicy < FundBasePolicy
  def index?
    true
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
    !record.approved && create? && user.has_cached_role?(:approver)
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
    record.unit_prices.present? && update?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end

  def reminder?
    update?
  end
end
