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
    return true if support?
    return permissioned_rm?(:update) if rm?

    if record.deal_investor.present?
      DealInvestorPolicy.new(user, record.deal_investor).update?
    else
      deal_update_permission?
    end
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

  def update_sequence?
    permissioned_employee?
  end

  def destroy?
    return true if support?
    return permissioned_rm?(:destroy) if rm?

    if record.deal_investor.present?
      DealInvestorPolicy.new(user, record.deal_investor).destroy?
    else
      deal_update_permission?
    end
  end

  private

  def deal_update_permission?
    return false if record.deal.blank?

    DealPolicy.new(user, record.deal).update?
  end
end
