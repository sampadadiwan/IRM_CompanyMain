class CapitalRemittancePolicy < FundBasePolicy
  def index?
    user.enable_funds
  end

  def show?
    permissioned_employee? ||
      permissioned_investor?
  end

  def new?
    create?
  end

  def allocate_units?
    update?
  end

  def preview?
    update?
  end

  def verify?
    update?
  end

  def send_notification?
    update? && record.capital_call.approved
  end

  def update?
    permissioned_employee?(:update)
  end

  def edit?
    update?
  end

  def generate_docs?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end
end
