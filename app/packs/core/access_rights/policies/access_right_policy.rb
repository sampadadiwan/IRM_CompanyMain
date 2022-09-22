class AccessRightPolicy < ApplicationPolicy
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
    user.has_cached_role?(:super) || (user.entity_id == record.entity_id)
  end

  def create?
    user.has_cached_role?(:super) || (user.entity_id == record.entity_id)
  end

  def new?
    create?
  end

  def update?
    create? || Pundit.policy(user, record.owner).update?
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
