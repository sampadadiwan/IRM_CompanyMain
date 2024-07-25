class SecondarySalePolicy < SaleBasePolicy
  # class Scope < Scope
  #   def resolve
  #     case user.curr_role.to_sym
  #     when :employee
  #       user.has_cached_role?(:company_admin) ? scope.where(entity_id: user.entity_id) : scope.for_employee(user)
  #     when :holding
  #       scope.for_investor(user).distinct
  #     when :investor
  #       scope.for_investor(user)
  #     else
  #       scope.none
  #     end
  #   end
  # end

  def index?
    user.enable_secondary_sale
  end

  def offer?
    permissioned_investor?(:seller)
  end

  def external_sale?
    user.has_cached_role?(:investor) && record.visible_externally
  end

  def owner?
    permissioned_employee?(:update)
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
      (buyer? || external_sale?)
  end

  def see_private_docs?
    permissioned_employee? ||
      user.entity.interests_shown.short_listed.where(secondary_sale_id: record.id).present?
  end

  def show?
    if (belongs_to_entity?(user, record) && user.enable_secondary_sale) || support?
      true
    else
      permissioned_investor? ||
        external_sale?
    end
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
