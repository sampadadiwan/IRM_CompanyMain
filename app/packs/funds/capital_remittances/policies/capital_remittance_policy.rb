class CapitalRemittancePolicy < FundBasePolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:company_admin) && user.entity_type == "Investment Fund"
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
    permissioned_employee? ||
      permissioned_investor? ||
      permissioned_advisor?
  end

  def new?
    create?
  end

  def allocate_units?
    update?
  end

  def verify?
    update?
  end

  def send_notification?
    update? && !record.notification_sent && record.capital_call.approved
  end

  def update?
    permissioned_employee?(:update) ||
      permissioned_advisor?(:update)
  end

  def edit?
    update?
  end

  def generate_docs?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy) ||
      permissioned_advisor?(:destroy)
  end
end
