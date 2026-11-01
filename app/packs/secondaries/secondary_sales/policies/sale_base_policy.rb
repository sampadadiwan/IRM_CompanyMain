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

  # H19: is this user acting for the selling firm (its company admins, its employees, or super /
  # support), as opposed to a seller, a buyer or an RM? Decides which fields of an offer or interest
  # they may send (OfferPolicy / InterestPolicy#permitted_attributes).
  # Defined here on the dispatcher and never delegated: SuperPolicy#method_missing answers true to
  # any question, so a delegated firm_side? would be true for anyone the dispatch can't place.
  # Support users dispatch to the Employee policy, so their verifications keep working.
  # Tests H19-1, H19-2, H19-H2 — features/security/secondaries_isolation.feature
  def firm_side?
    # A signed shared link never acts for the firm, whoever opened it
    return false if signed_id_access?

    # The role-based dispatch: RM and investor / advisor / holding personas are never the firm
    policy_class = specific_policy_class
    return false if policy_class.nil?

    policy_class == SuperPolicy || policy_class.name.end_with?("CompanyAdminPolicy", "EmployeePolicy")
  end

  def specific_policy
    policy_class = specific_policy_class
    Rails.logger.debug { "####### Policy class: #{policy_class}" }
    policy_class.new(user, record)
  end

  def specific_policy_class
    model_class = record.instance_of?(Class) ? record : record.class

    if user.has_cached_role?(:rm)
      "#{model_class}RmPolicy".constantize
    elsif user.curr_role.to_s == "investor" || user.curr_role.to_s == "advisor" || user.has_cached_role?(:holding)
      "#{model_class}InvestorPolicy".constantize
    elsif user.has_cached_role?(:company_admin)
      "#{model_class}CompanyAdminPolicy".constantize
    elsif user.has_cached_role?(:employee)
      "#{model_class}EmployeePolicy".constantize
    elsif user.has_cached_role?(:super) || user.has_cached_role?(:support)
      "SuperPolicy".constantize
    end
  end
end
