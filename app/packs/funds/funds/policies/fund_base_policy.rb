class FundBasePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.curr_role == "investor"
        scope.for_investor(user)
      elsif user.has_cached_role?(:company_admin) && (user.entity.is_fund? || user.entity.is_group_company?)
        scope.for_company_admin(user)
      elsif user.has_cached_role?(:employee) && (user.entity.is_fund? || user.entity.is_group_company?)
        scope.for_employee(user)
      else
        scope.none
      end
    end
  end

  def permissioned_employee?(perm = nil)
    fund_id = record.instance_of?(Fund) ? record.id : record.fund_id
    super(fund_id, "Fund", perm)
  end

  def create?
    permissioned_employee?(:create)
  end
end
