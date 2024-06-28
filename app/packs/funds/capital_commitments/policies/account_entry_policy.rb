class AccountEntryPolicy < FundBasePolicy
  def index?
    user.curr_role != "investor"
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
    !record.generated &&

      permissioned_employee?(:update)
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end
end
