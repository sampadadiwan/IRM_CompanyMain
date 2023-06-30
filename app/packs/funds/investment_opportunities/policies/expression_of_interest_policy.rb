class ExpressionOfInterestPolicy < IoBasePolicy
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

  def edit?
    update?
  end

  def generate_documentation?
    update? && !record.esign_completed
  end

  def destroy?
    permissioned_employee?(:destroy)
  end

  def approve?
    update?
  end

  def allocate?
    update?
  end

  def allocation_form?
    update?
  end
end
