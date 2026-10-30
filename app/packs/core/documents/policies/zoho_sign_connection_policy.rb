# Exactly the people who may edit the company's settings: its company admins (not investor
# advisors) and CapHive support (X1, X2). The record always carries the entity from the URL.
class ZohoSignConnectionPolicy < ApplicationPolicy
  def show?
    EntityPolicy.new(user, record.entity).update?
  end

  def create?
    show?
  end

  def update?
    show?
  end

  def destroy?
    show?
  end

  def verify?
    show?
  end

  def reveal_webhook_secret?
    show?
  end

  def regenerate_webhook_secret?
    show?
  end
end
