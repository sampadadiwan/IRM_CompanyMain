class InvestorKycPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.curr_role.to_sym == :startup
        scope.where(entity_id: user.entity_id)
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
      user.id == record.user_id
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
