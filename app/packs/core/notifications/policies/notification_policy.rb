class NotificationPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.curr_role == "investor"
        scope.where(recipient_type: "User", recipient_id: user.id)
      else
        scope.where(entity_id: user.entity_id).or(scope.where(recipient_type: "User", recipient_id: user.id))
      end
    end
  end

  def index?
    true
  end

  def show?
    (user.id == record.recipient_id && record.recipient_type == "User") || record.entity_id == user.entity_id || super_user?
  end

  def mark_as_read?
    user.id == record.recipient_id && record.recipient_type == "User"
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
