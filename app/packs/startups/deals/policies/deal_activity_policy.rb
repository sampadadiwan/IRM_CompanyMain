class DealActivityPolicy < DealBasePolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.curr_role == "advisor"
        scope.for_advisor(user)
      else
        scope.where("entity_id=?", user.entity_id)
      end
    end
  end

  def index?
    true
  end

  def show?
    (user.has_cached_role?(:super) || (user.entity_id == record.entity_id)) ||
      (record.deal_investor && record.deal_investor.investor_entity_id == user.entity_id) ||
      permissioned_advisor?
  end

  def create?
    user.has_cached_role?(:super) || (user.entity_id == record.entity_id)
  end

  def new?
    create?
  end

  def update?
    create? ||
      permissioned_advisor?(:update)
  end

  def edit?
    update?
  end

  def destroy?
    create? ||
      permissioned_advisor?(:destroy)
  end
end
