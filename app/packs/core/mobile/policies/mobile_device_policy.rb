# A user sees and signs out only their own phones (lp-mobile-app design card ③, QA R6/R7).
class MobileDevicePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(user_id: user.id)
    end
  end

  def index?
    true
  end

  def update?
    own?
  end

  def destroy?
    own?
  end

  private

  def own?
    record.user_id == user.id
  end
end
