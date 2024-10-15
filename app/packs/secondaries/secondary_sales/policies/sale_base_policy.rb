class SaleBasePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:rm)
        scope.for_rm(user)
      elsif user.curr_role == "investor"
        scope.for_investor(user)
      elsif user.has_cached_role?(:company_admin) && ["Company", "Group Company"].include?(user.entity_type)
        scope.for_company_admin(user)
      elsif user.has_cached_role?(:employee) && ["Company", "Group Company"].include?(user.entity_type)
        scope.for_employee(user)
      elsif user.curr_role == 'holding'
        scope.for_investor(user).distinct
      else
        scope.none
      end
    end
  end

  def create?
    (belongs_to_entity?(user, record) && user.has_cached_role?(:company_admin)) ||
      permissioned_employee?(:create)
  end

  def specific_policy
    policy_class = specific_policy_class
    Rails.logger.debug { "####### Policy class: #{policy_class}" }
    policy_class.new(user, record)
  end

  def specific_policy_class
    if user.has_cached_role?(:rm)
      "#{record.class}RmPolicy".constantize
    elsif user.curr_role.to_s == "investor" || user.has_cached_role?(:holding)
      "#{record.class}InvestorPolicy".constantize
    elsif user.has_cached_role?(:company_admin)
      "#{record.class}CompanyAdminPolicy".constantize
    elsif user.has_cached_role?(:employee)
      "#{record.class}EmployeePolicy".constantize
    elsif user.has_cached_role?(:super) || user.has_cached_role?(:support)
      "SuperPolicy".constantize
    end
  end
end
