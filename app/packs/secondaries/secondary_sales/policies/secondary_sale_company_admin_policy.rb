class SecondarySaleCompanyAdminPolicy < SaleBasePolicy
  def index?
    user.enable_secondary_sale
  end

  def offer?
    record.active? && permissioned_employee?(:update) && record.manage_offers
  end

  def owner?
    permissioned_employee?
  end

  def offers?
    permissioned_employee?(:update)
  end

  def interests?
    permissioned_employee?(:update)
  end

  def payments?
    owner?
  end

  def show_interest?
    record.active? && permissioned_employee?(:update) && record.manage_interests
  end

  def see_private_docs?
    permissioned_employee?
  end

  def show?
    permissioned_employee?
  end

  def report?
    show?
  end

  def create?
    user.enable_secondary_sale && permissioned_employee?(:create)
  end

  def new?
    create?
  end

  def update?
    user.enable_secondary_sale && record.active &&
      permissioned_employee?(:update)
  end

  def generate_spa?
    update? && record.active
  end

  def send_notification?
    update?
  end

  def notify_allocations?
    update?
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
