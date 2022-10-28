class InvestorKycPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if %i[startup fund_manager].include? user.curr_role.to_sym
        scope.where(entity_id: user.entity_id)
      elsif user.has_cached_role?(:accountant)
        scope.for_accountant(user)
      else
        scope.where(user_id: user.id)
      end
    end
  end

  def index?
    true
  end

  def show?
    user.entity_id == record.entity_id ||
      user.id == record.user_id ||
      record.entity.accountant?(user)
  end

  def create?
    (user.entity_id == record.entity_id) ||
      user.id == record.user_id
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
