class NotificationPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(recipient_type: "User", recipient_id: user.id).or(scope.where(recipient_type: "Entity", recipient_id: user.entity_id))
    end
  end

  def index?
    true
  end

  def show?
    (user.id == record.recipient_id && record.recipient_type == "User") || (user.entity_id == record.recipient_id && record.recipient_type == "Entity") || super_user?
  end

  def mark_as_read?
    show?
  end

  def create?
    false
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
