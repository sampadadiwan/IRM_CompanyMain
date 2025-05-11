class ExpressionOfInterestPolicy < IoBasePolicy
  def index?
    user.enable_inv_opportunities
  end

  def show?
    permissioned_employee? ||
      permissioned_investor? ||
      permissioned_rm?
  end

  def create?
    belongs_to_entity?(user, record) ||
      permissioned_employee?(:create) ||
      permissioned_rm? || permissioned_investor?
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update) ||
      permissioned_investor?
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
    update? && user.has_cached_role?(:approver)
  end

  def allocate?
    update?
  end

  def allocation_form?
    update?
  end
end
