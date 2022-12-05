class SecondarySalePolicy < SaleBasePolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.curr_role.to_sym == :company
        scope.where(entity_id: user.entity_id)
      elsif user.curr_role.to_sym == :advisor
        scope.for_advisor(user)
      elsif %i[holding investor].include?(user.curr_role.to_sym)
        scope.for(user).distinct
      elsif user.curr_role.to_sym == :secondary_buyer
        scope.where(visible_externally: true)
      else
        scope.none
      end
    end
  end

  def index?
    user.enable_secondary_sale
  end

  def offer?
    permissioned_investor?(:seller)
  end

  def external_sale?
    (user.has_cached_role?(:secondary_buyer) && record.visible_externally)
  end

  def owner?
    permissioned_employee?(:update) ||
      permissioned_advisor?(:update)
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
      (permissioned_investor?(:buyer) || external_sale?)
  end

  def see_private_docs?
    permissioned_advisor? ||
      permissioned_employee? ||
      user.entity.interests_shown.short_listed.where(secondary_sale_id: record.id).present?
  end

  def show?
    if user.entity_id == record.entity_id && user.enable_secondary_sale
      true
    else
      (permissioned_advisor? ||
        permissioned_investor? ||
        external_sale?)
    end
  end

  def create?
    user.enable_secondary_sale &&
      (permissioned_employee?(:create) || permissioned_advisor?(:create))
  end

  def new?
    create?
  end

  def update?
    user.enable_secondary_sale && !record.finalized &&
      (permissioned_employee?(:update) || permissioned_advisor?(:update))
  end

  def spa_upload?
    update?
  end

  def generate_spa?
    create? && record.spa
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
    create?
  end

  def view_allocations?
    create? || owner?
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy) ||
      permissioned_advisor?(:destroy)
  end

  def buyer?
    permissioned_investor?("Buyer")
  end

  def seller?
    permissioned_investor?("Seller")
  end
end
