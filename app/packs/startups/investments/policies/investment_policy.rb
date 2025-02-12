class InvestmentPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.entity_type == "Group Company"
        scope.where(entity_id: user.entity.child_ids)
      else
        scope.where(entity_id: user.entity_id)
      end
    end
  end

  def index?
    user.enable_investments
  end

  def show?
    permissioned_employee? && user.enable_investments
  end

  def create?
    user.enable_investments
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update)
  end

  def edit?
    create?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end
end
