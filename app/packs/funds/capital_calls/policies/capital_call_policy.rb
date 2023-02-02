class CapitalCallPolicy < FundBasePolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.has_cached_role?(:company_admin) && user.entity_type == "Investment Fund"
        scope.where(entity_id: user.entity_id)
      elsif user.has_cached_role?(:employee) && user.entity_type == "Investment Fund"
        scope.for_employee(user)
      elsif user.curr_role.to_sym == :advisor
        scope.for_advisor(user)
      else
        scope.for_investor(user)
      end
    end
  end

  def index?
    true
  end

  def show?
    permissioned_investor? ||
      permissioned_employee? ||
      permissioned_advisor?
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update) ||
      permissioned_advisor?(:update)
  end

  def approve?
    !record.approved && create? && user.has_cached_role?(:approver)
  end

  def edit?
    update?
  end

  def generate_docs?
    update?
  end

  def allocate_units?
    record.unit_prices.present? && update?
  end

  def destroy?
    permissioned_employee?(:destroy) ||
      permissioned_advisor?(:destroy)
  end

  def reminder?
    update?
  end
end
