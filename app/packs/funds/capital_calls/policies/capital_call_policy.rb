class CapitalCallPolicy < FundBasePolicy
  def index?
    user.enable_funds
  end

  def create?
    permissioned_employee?(:create)
  end

  def show?
    permissioned_employee?
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update)
  end

  def approve?
    !record.approved && update? && user.has_cached_role?(:approver)
  end

  def unapprove?
    record.approved && update? && user.has_cached_role?(:approver)
  end

  def edit?
    update?
  end

  def recompute_fees?
    update?
  end

  def generate_docs?
    !record.approved && update?
  end

  def allocate_units?
    record.approved && record.unit_prices.present? && update?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end

  def reminder?
    update? && record.approved
  end

  def notify?
    update? && record.approved
  end

  # Only company_admin can assign / remove a workflow template on a capital call,
  # and only when the entity has workflow_templates enabled.
  def assign_workflow?
    user.entity&.permissions&.enable_workflow_templates? && user.company_admin? && belongs_to_entity?(user, record)
  end
end
