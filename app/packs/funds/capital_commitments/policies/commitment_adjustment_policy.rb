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
    # Only allow destroy if the record is not with owner_type of CapitalRemittance and the user has permission to destroy
    # For CapitalRemittance, we handle the destroy manually as the adjustment results in a CapitalRemittancePayment (see AdjustmentCreate) that is liked to this adjustment only by notes field. And hence has to be deleted manually
    permissioned_employee?(:destroy) && record.owner_type != "CapitalRemittance"
  end
end
