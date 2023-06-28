class DealActivityPolicy < DealBasePolicy
  class Scope < Scope
    def resolve
      if user.entity_type == "Group Company"
        scope.where(entity_id: user.entity.child_ids)
      else
        scope.joins(:deal_investor).where("deal_activities.entity_id=? or deal_investors.investor_entity_id=?", user.entity_id, user.entity_id)
      end
    end
  end

  def index?
    true
  end

  def show?
    permissioned_employee? ||
      (record.deal_investor && record.deal_investor.investor_entity_id == user.entity_id)
  end

  def create?
    permissioned_employee?(:create)
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update)
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
    permissioned_employee?(:destroy)
  end
end
