class SecondarySalePolicy < SaleBasePolicy
  def index?
    user.enable_secondary_sale
  end

  def offer?
    record.active? &&
      (
        permissioned_investor?(:seller) ||
        (permissioned_employee?(:update) && record.manage_offers)
      )
  end

  def external_sale?
    user.has_cached_role?(:investor) && record.visible_externally
  end

  def owner?
    permissioned_employee? # (:update)
  end

  def offers?
    owner? || permissioned_investor?(:seller)
  end

  def interests?
    owner? || show_interest?
  end

  def finalize_offer_allocation?
    owner?
  end

  def payments?
    owner?
  end

  def finalize_interest_allocation?
    owner?
  end

  def show_interest?
    record.active? &&
      (buyer? || (permissioned_employee?(:update) && record.manage_interests))
  end

  def see_private_docs?
    permissioned_employee? ||
      user.entity.interests_shown.short_listed.where(secondary_sale_id: record.id).present?
  end

  def show?
    permissioned_employee? ||
      permissioned_investor?
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
    (user.enable_secondary_sale && !record.finalized &&
      permissioned_employee?(:update)) || support?
  end

  def spa_upload?
    update?
  end

  def generate_spa?
    create? && record.active
  end

  def finalize_allocation?
    update?
  end

  def make_visible?
    update?
  end

  def lock_allocations?
    create?
  end

  def send_notification?
    create?
  end

  def notify_allocations?
    create?
  end

  def download?
    create?
  end

  def allocate?
    create?
  end

  def approve_offers?
    user.has_cached_role?(:approver) && create?
  end

  def view_allocations?
    create? || owner?
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end

  def buyer?
    permissioned_investor?("Buyer")
  end

  def seller?
    permissioned_investor?("Seller")
  end
end
