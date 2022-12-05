class ValuationPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.curr_role == "company" || user.curr_role == "fund_manager"
        scope.where(entity_id: user.entity_id)
      else
        scope.none
      end
    end
  end

  def index?
    true
  end

  def show?
    (user.entity_id == record.entity_id) ||
      (record.owner && owner_policy.show?)
  end

  def create?
    (user.entity_id == record.entity_id)
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    create?
  end

  def destroy?
    create?
  end

  def owner_policy
    Pundit.policy(user, record.owner)
  end
end
