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

  def owner?
    user.entity_id == record.entity_id
  end

  def buyer?
    record.buyer?(user)
  end

  def seller?
    record.seller?(user)
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
        external_sale? ||
        allow_external?(:read))
    end
  end

  def create?
    (user.entity_id == record.entity_id && user.entity.enable_secondary_sale)
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
    update? && record.allocation_percentage.positive?
  end

  def make_visible?
    update?
  end

  def lock_allocations?
    create?
  end

  def send_notification?
    update? && !record.lock_allocations
  end

  def notify_allocations?
    update? && !record.lock_allocations
  end

  def download?
    create?
  end

  def allocate?
    update?
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
