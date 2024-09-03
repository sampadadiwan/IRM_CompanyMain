class CommitmentAdjustmentPolicy < FundBasePolicy
  def index?
    user.enable_funds
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

  # TODO: Check this policy, unsure why this is like this.
  def create?
    permissioned_employee?(:create) &&
      new_policy(record.capital_commitment).update? && # The associated capital_commitment must be editable
      (record.owner.nil? || new_policy(record.owner).update?) # The associated owner must be editable
  end

  def update?
    false # permissioned_employee?(:update)
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end
end
