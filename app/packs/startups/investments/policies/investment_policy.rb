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
    # D: the investment is the user's firm's, and so is its portfolio company (there was no firm check)
    user.enable_investments && belongs_to_entity?(user, record) && parent_in_users_firms?(record.portfolio_company)
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
