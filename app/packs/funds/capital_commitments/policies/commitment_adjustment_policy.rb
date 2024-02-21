class CommitmentAdjustmentPolicy < FundBasePolicy
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

  def create?
    ((belongs_to_entity?(user, record) && user.has_cached_role?(:company_admin)) ||
      permissioned_employee?(:create)) &&
      new_policy(record.capital_commitment).update? && # The associated capital_commitment must be editable
      (record.owner.nil? || new_policy(record.owner).update?) # The associated owner must be editable
  end

  def update?
    false # permissioned_employee?(:update)
  end

  def edit?
    false # update?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end
end
