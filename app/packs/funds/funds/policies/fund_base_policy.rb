class FundBasePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:rm)
        scope.for_rm(user)
      elsif user.curr_role == "investor"
        scope.for_investor(user)
      elsif user.has_cached_role?(:company_admin) && (user.entity.is_fund? || user.entity.is_group_company?)
        scope.for_company_admin(user)
      elsif user.has_cached_role?(:employee) && (user.entity.is_fund? || user.entity.is_group_company?)
        scope.for_employee(user)
      elsif user.has_cached_role?(:super)
        scope.all
      else
        scope.none
      end
    end
  end

  def create?
    permissioned_employee?(:create)
  end

  # H6 step 2 — the class-level gate WithBulkActions#bulk_actions checks before queuing a fund bulk
  # action (remittances, calls, distributions, formulas, units, ratios). Every fund bulk action is a
  # staff action, so LPs and other investor personas are refused outright; which rows a staff user may
  # change is re-checked per record in the job. Tests H6-1, H6-3, H6-H1 —
  # features/security/bulk_actions_authorization.feature
  def bulk_actions?
    index? && !user.curr_role_investor?
  end
end
