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
    permissioned_employee? ||
      (record.deal_investor && record.deal_investor.investor_entity_id == user.entity_id) ||
      permissioned_advisor?
  end

  def create?
    permissioned_employee?(:create)
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update) ||
      permissioned_advisor?(:update)
  end

  def edit?
    update?
  end

  def toggle_completed?
    update?
  end

  def update_sequence?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy) ||
      permissioned_advisor?(:destroy)
  end
end
