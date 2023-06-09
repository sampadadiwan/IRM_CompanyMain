class AccountEntryPolicy < FundBasePolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:company_admin) && user.entity_type == "Investment Fund"
        scope.where(entity_id: user.entity_id)
      elsif user.curr_role == 'employee' && user.entity_type == "Investment Fund"
        scope.for_employee(user)
      else
        scope.for_investor(user)
      end
    end
  end

  def index?
    true
  end

  def report?
    update?
  end

  def show?
    permissioned_employee? ||
      permissioned_investor?
  end

  def new?
    create?
  end

  def update?
    !record.generated &&

      permissioned_employee?(:update)
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end
end
