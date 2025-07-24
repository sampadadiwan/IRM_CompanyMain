class InterestEmployeePolicy < SaleBasePolicy
  def index?
    user.enable_secondary_sale
  end

  def owner?
    permissioned_employee?
  end

  def matched_offer?
    permissioned_employee?
  end

  def show?
    permissioned_employee?
  end

  def generate_docs?
    permissioned_employee?(:update) && record.short_listed
  end

  def short_list?
    permissioned_employee?(:update)
  end

  def send_email_to_change?
    false
  end

  def create?
    permissioned_employee?(:update) && record.secondary_sale.manage_interests
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update) && record.secondary_sale.manage_interests && !record.verified
  end

  def accept_spa?
    false
  end

  def matched_offers?
    true
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:update) && !record.verified
  end
end
