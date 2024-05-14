class DealActivityPolicy < DealBasePolicy
  class Scope < Scope
    def resolve
      if user.entity_type == "Group Company"
        scope.where(entity_id: user.entity.child_ids)
      else
        scope.where("deal_activities.entity_id=?", user.entity_id)
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

  def perform_activity_action?
    update?
  end

  def update_sequences?
    permissioned_employee?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end
end
