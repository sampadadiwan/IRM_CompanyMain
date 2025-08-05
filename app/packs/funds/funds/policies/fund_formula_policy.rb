class FundFormulaPolicy < FundBasePolicy
  def index?
    user.enable_funds
  end

  def show?
    permissioned_employee?
  end

  # Only support can create / update formulas
  def create?
    support?
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update)
  end

  def enable_formulas?
    update?
  end

  def edit?
    update?
  end

  # Confirm who should have access
  def generate_ai_descriptions?
    user.enable_funds
  end

  def destroy?
    update?
  end
end
