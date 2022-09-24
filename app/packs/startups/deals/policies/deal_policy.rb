class DealPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.has_cached_role?(:startup)
        scope.where(entity_id: user.entity_id)
      elsif user.has_cached_role?(:investor)
        Deal.for_investor(user)
      end
    end
  end

  def index?
    user.enable_deals
  end

  def show?
    if user.has_cached_role?(:super) || (user.entity_id == record.entity_id && user.enable_deals)
      true
    else
      false
      # user.enable_deals &&
      #   Deal.for_investor(user).where("deals.id=?", record.id).first.present?
    end
  end

  def create?
    user.has_cached_role?(:super) || (user.entity_id == record.entity_id && user.enable_deals)
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def start_deal?
    update?
  end

  def recreate_activities?
    start_deal?
  end

  def edit?
    create?
  end

  def destroy?
    create?
  end
end
