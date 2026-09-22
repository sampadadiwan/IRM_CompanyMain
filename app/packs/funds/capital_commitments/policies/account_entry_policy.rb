class AccountEntryPolicy < FundBasePolicy
  def index?
    user.enable_funds && user.curr_role != "investor"
  end

  def adhoc?
    index?
  end

  def create?
    permissioned_employee?(:create)
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

  def explain?
    show?
  end

  # Opening a line of the entry page's "How this was worked out" card walks into other entries,
  # the fund-level entries a share came from, and the fund's own formulas. show? also admits
  # investors, who may read their own entries but have no business reading the fund's workings,
  # so this is narrower. set_account_entry authorizes by action name, so it must be called this.
  def explanation_node?
    permissioned_employee?
  end
end
