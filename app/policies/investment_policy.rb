class InvestmentPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      else
        scope.where(investee_entity_id: user.entity_id)
      end
    end
  end

  def index?
    user.entity.enable_investments
  end

  def show?
    if user.entity_id == record.investee_entity_id && user.entity.enable_investments
      true
    else
      user.entity.enable_investments &&
        Investment.for_investor(user, record.investee_entity)
                  .where("investments.id=?", record.id).first.present?
    end
  end

  def create?
    (user.entity_id == record.investee_entity_id && user.entity.enable_investments)
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    create? && !record.employee_holdings
  end

  def destroy?
    create?
  end
end
