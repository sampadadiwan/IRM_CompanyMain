class OfferPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.has_cached_role?(:holding)
        scope.where(user_id: user.id)
      elsif user.has_cached_role?(:investor)
        scope.joins(:investor).where('investors.investor_entity_id': user.entity_id)
      else
        scope.where(entity_id: user.entity_id)
      end
    end
  end

  def index?
    true
  end

  def show?
    create?
  end

  def create?
    if user.has_cached_role?(:super) || (user.entity_id == record.entity_id)
      true
    elsif user.has_cached_role?(:holding)
      record.holding.user_id == user.id && record.holding.entity_id == record.entity_id
    elsif user.has_cached_role?(:investor)
      record.holding.investor.investor_entity_id == user.entity_id && record.holding.entity_id == record.entity_id
    else
      false
    end
  end

  def approve?
    user.has_cached_role?(:approver) && (user.entity_id == record.entity_id)
  end

  def new?
    create?
  end

  def update?
    user.id == record.user_id # && !record.approved
  end

  def allocation_form?
    SecondarySalePolicy.new(user, record.secondary_sale).update?
  end

  def allocate?
    SecondarySalePolicy.new(user, record.secondary_sale).update?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
