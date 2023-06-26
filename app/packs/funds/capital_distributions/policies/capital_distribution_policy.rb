class CapitalDistributionPolicy < FundBasePolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:company_admin) && user.entity_type == "Investment Fund"
        scope.where(entity_id: user.entity_id)
      elsif user.curr_role == "employee" && user.entity_type == "Investment Fund"
        scope.for_employee(user)
      elsif user.entity_type == "Group Company"
        scope.for_parent_employee(user)
      else
        scope.for_investor(user).distinct
      end
    end
  end

  def index?
    true
  end

  def show?
    permissioned_employee? ||
      permissioned_investor?
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update)
  end

  def payments_completed?
    update?
  end

  def approve?
    !record.approved && create? && user.has_cached_role?(:approver)
  end

  def redeem_units?
    record.unit_prices.present? && update?
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end

  def reminder?
    update?
  end
end
