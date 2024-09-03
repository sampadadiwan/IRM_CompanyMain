class CustomNotificationPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    true
  end

  def show?
    belongs_to_entity?(user, record)
  end

  def mark_as_read?
    show?
  end

  def create?
    show? && Pundit.policy(user, record.owner).update?
  end

  def new?
    create?
  end

  def update?
    # Templates can be edited only by support, for security reasons
    record.is_erb ? support? : create?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
