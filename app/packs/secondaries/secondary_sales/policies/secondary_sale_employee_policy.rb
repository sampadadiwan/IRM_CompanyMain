class SecondarySaleEmployeePolicy < SaleBasePolicy
  def index?
    user.enable_secondary_sale
  end

  def offer?
    record.active? && show? && record.manage_offers
  end

  def owner?
    permissioned_employee?
  end

  def offers?
    show?
  end

  def interests?
    show?
  end

  def payments?
    owner?
  end

  def show_interest?
    record.active? && show? && record.manage_offers
  end

  def see_private_docs?
    show?
  end

  def show?
    permissioned_employee?
  end

  def report?
    show?
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

  def generate_spa?
    update? && record.active
  end

  def send_notification?
    owner?
  end

  def notify_allocations?
    owner?
  end

  def download?
    owner?
  end

  def allocate?
    update?
  end

  def approve_offers?
    user.has_cached_role?(:approver) && update?
  end

  def short_list_interests?
    user.has_cached_role?(:approver) && update?
  end

  def view_allocations?
    owner?
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end

  def buyer?
    false
  end

  def seller?
    false
  end
end
