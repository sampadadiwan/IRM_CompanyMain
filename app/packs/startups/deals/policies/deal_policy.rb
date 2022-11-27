class DealPolicy < DealBasePolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif %w[startup fund_manager].include? user.curr_role
        scope.where(entity_id: user.entity_id)
      elsif user.curr_role == "investor"
        scope.for_investor(user)
      elsif user.curr_role == "advisor"
        scope.for_advisor(user)
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
      permissioned_advisor?
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
