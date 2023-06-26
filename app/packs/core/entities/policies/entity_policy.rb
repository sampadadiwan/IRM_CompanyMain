class EntityPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.curr_role.to_sym == :investor
        scope.for_investor(user)
      else
        scope.none
      end
    end

    def resolve_admin
      #scope.where(enable_support: true)
      scope.all
    end
  end

  def index?
    true
  end

  def dashboard?
    true
  end

  def search?
    true
  end

  def show?
    if user.entity_id == record.id || super_user?
      true
    else
      user.entity_id != record.id
    end
  end

  def create?
    user.has_cached_role?(:super)
  end

  def new?
    update?
  end

  def update?
    ((user.entity_id == record.id) && user.curr_role != "holding" && user.has_cached_role?(:company_admin)) || super_user?
  end

  def edit?
    update?
  end

  def approve_all_holdings?
    update? && user.has_cached_role?(:approver)
  end

  def destroy?
    false
  end

  def view_investments?
    user.entity_id == record.id || investment_access?
  end

  def investment_access?
    investor = Investor.for(user, record).first
    record.access_rights.investments.exists?(access_to_investor_id: investor.id)
  end
end
