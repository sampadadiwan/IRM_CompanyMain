class SaleBasePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.curr_role == "investor"
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

  def permissioned_employee?(perm = nil)
    secondary_sale_id = record.instance_of?(SecondarySale) ? record.id : record.secondary_sale_id
    super(secondary_sale_id, "SecondarySale", perm)
  end

  def permissioned_investor?(metadata = "none")
    super
  end

  def create?
    (belongs_to_entity?(user, record) && user.has_cached_role?(:company_admin)) ||
      permissioned_employee?(:create)
  end
end
