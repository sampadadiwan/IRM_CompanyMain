class AccessRightPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    true
  end

  def show?
    (user.entity_id == record.entity_id) || super_user?
  end

  def create?
    (user.entity_id == record.entity_id)
  end

  def new?
    create?
  end

  def update?
    create? || Pundit.policy(user, record.owner).update? || super_user?
  end

  def start_deal?
    update?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
