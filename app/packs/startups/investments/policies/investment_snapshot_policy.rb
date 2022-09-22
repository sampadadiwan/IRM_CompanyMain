class InvestmentSnapshotPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.curr_role == "startup"
        scope.where(entity_id: user.entity_id)
      end
    end
  end

  def index?
    user.entity.enable_investments
  end

  def show?
    true
  end

  def create?
    false
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
end
