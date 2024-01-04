class FundPolicy < FundBasePolicy
  def index?
    user.enable_funds
  end

  def report?
    show?
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

  def check_access_rights?
    update?
  end

  def generate_documentation?
    update?
  end

  def show?
    user.enable_funds &&
      (
        permissioned_employee? ||
        permissioned_investor? ||
        super_user?
      )
  end

  def generate_fund_ratios?
    update?
  end

  def last?
    update?
  end

  def timeline?
    show?
  end

  def create?
    user.enable_funds &&
      permissioned_employee?(:create)
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update) || super_user?
  end

  def edit?
    update?
  end

  def delete_all?
    user.has_cached_role?(:company_admin) && permissioned_employee?(:update)
  end

  def destroy?
    Rails.env.test? ? permissioned_employee?(:destroy) : super_user?
  end

  def grant_access_rights?
    user.has_cached_role?(:company_admin)
  end
end
