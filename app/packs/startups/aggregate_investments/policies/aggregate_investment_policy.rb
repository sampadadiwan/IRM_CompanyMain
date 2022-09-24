class AggregateInvestmentPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      else
        scope.where(entity_id: user.entity_id)
      end
    end
  end

  def index?
    true
  end

  def show?
    if user.has_cached_role?(:super) || (user.entity_id == record.entity_id)
      true
    else
      user.enable_investments &&
        AggregateInvestment.for_investor(user, record.entity)
                           .where("aggregate_investments.id=?", record.id).first.present?
    end
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
