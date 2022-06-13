class SecondarySalePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.curr_role.to_sym == :startup
        scope.where(entity_id: user.entity_id)
      elsif %i[holding investor].include?(user.curr_role.to_sym)
        scope.for(user).or(scope.where(visible_externally: true)).distinct
      elsif user.curr_role.to_sym == :secondary_buyer
        scope.where(visible_externally: true)
      else
        scope.none
      end
    end
  end

  def index?
    user.entity.enable_secondary_sale
  end

  def offer?
    seller?
  end

  def external_sale?
    (user.has_cached_role?(:secondary_buyer) && record.visible_externally)
  end

  def buyer?
    SecondarySale.for(user).where("access_rights.metadata=?", "Buyer").where(id: record.id).present?
  end

  def seller?
    SecondarySale.for(user).where("access_rights.metadata=?", "Seller").where(id: record.id).present?
  end

  def show_interest?
    record.active? &&
      (buyer? || external_sale?)
  end

  def see_private_docs?
    user.entity_id == record.entity_id || user.entity.interests_shown.short_listed.where(secondary_sale_id: record.id).present?
  end

  def show?
    if user.entity_id == record.entity_id && user.entity.enable_secondary_sale
      true
    else
      record.active? &&
        (SecondarySale.for(user).where(id: record.id).present? ||
        external_sale?)
    end
  end

  def create?
    user.has_cached_role?(:super) || (user.entity_id == record.entity_id && user.entity.enable_secondary_sale)
  end

  def new?
    create?
  end

  def update?
    create? && !record.finalized
  end

  def spa_upload?
    update?
  end

  def finalize_allocation?
    update?
  end

  def make_visible?
    update?
  end

  def download?
    create?
  end

  def allocate?
    update?
  end

  def notify_allocation?
    create?
  end

  def view_allocations?
    create?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
