class FundPolicy < FundBasePolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:company_admin) && user.entity_type == "Investment Fund"
        scope.where(entity_id: user.entity_id)
      elsif user.curr_role == "employee" && user.entity_type == "Investment Fund"
        scope.for_employee(user)
      else
        scope.for_investor(user)
      end
    end
  end

  def index?
    user.enable_funds
  end

  def report?
    update?
  end

  def allocate?
    update?
  end

  def copy_formulas?
    update?
  end

  def allocate_form?
    update?
  end

  def export?
    update?
  end

  def show?
    user.enable_funds &&
      (
        permissioned_employee? ||
        permissioned_investor?
      )
  end

  def generate_fund_ratios?
    update?
  end

  def last?
    update?
  end

  def timeline?
    update?
  end

  def create?
    user.enable_funds &&
      permissioned_employee? &&
      user.entity_type == "Investment Fund"
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update)
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end
end
