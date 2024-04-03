class RolePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.none
    end
  end

  def destroy?
    support?
  end
end
