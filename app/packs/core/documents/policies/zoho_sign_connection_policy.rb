# CapHive support only (X1, X2): company admins neither see the panel nor reach these actions.
# support? also holds while support is logged in as a client user.
class ZohoSignConnectionPolicy < ApplicationPolicy
  def show?
    support?
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
