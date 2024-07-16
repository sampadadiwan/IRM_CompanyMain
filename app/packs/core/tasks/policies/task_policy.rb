class TaskPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.support?
        # Support user
        scope.where("entity_id=? or for_entity_id=?", user.entity_id, user.entity_id)
      else
        # Show tasks which are not for support only
        scope.where("entity_id=? or for_entity_id=?", user.entity_id, user.entity_id).not_for_support
      end
    end
  end

  def index?
    true
  end

  def show?
    if support?
      create?
    else
      create? && record.for_support == false
    end
  end

  def create?
    if belongs_to_entity?(user, record)
      true
    else
      user.entity_id == record.for_entity_id
    end
  end

  def new?
    create?
  end

  def update?
    create? # || (record.owner && Pundit.policy(user, record.owner).show?)
  end

  def completed?
    update?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
