class IoBasePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:rm)
        scope.for_rm(user)
      elsif user.curr_role == "investor"
        scope.for_investor(user)
      elsif user.has_cached_role?(:company_admin)
        scope.for_company_admin(user)
      elsif user.has_cached_role?(:employee)
        scope.for_employee(user)
      else
        scope.none
      end
    end
  end

  def create?
    permissioned_employee?(:create)
  end
end
