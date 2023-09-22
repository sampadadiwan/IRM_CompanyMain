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
