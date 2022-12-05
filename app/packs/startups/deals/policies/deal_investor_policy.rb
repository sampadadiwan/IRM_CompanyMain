class DealInvestorPolicy < DealBasePolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif %w[company fund_manager].include? user.curr_role
        scope.where(entity_id: user.entity_id)
      elsif user.curr_role == "investor"
        scope.for_investor(user)
      elsif user.curr_role == "advisor"
        scope.for_advisor(user)
      end
    end
  end

  def index?
    true
  end

  def show?
    (user.entity_id == record.entity_id) ||
      (user.entity_id == record.investor_entity_id) ||
      permissioned_advisor?
  end

  def create?
    (user.entity_id == record.entity_id)
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
