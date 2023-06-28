class AccessRightPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    belongs_to_entity?(user, record) || super_user?
  end

  def create?
    belongs_to_entity?(user, record)
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
