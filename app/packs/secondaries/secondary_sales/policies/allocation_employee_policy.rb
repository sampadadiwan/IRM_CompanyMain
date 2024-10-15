class AllocationEmployeePolicy < SaleBasePolicy
  def bulk_actions?
    user.enable_secondary_sale && permissioned_employee?(:update)
  end

  def index?
    user.enable_secondary_sale
  end

  def show?
    permissioned_employee?
  end

  def create?
    permissioned_employee?(:create)
  end

  def generate_docs?
    update?
  end

  def accept_spa?
    false
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
    permissioned_employee?(:destroy) && !record.verified?
  end
end
