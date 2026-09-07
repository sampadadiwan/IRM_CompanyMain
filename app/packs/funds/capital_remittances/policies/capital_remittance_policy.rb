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
    record.verified && Pundit.policy(user, record.capital_call).allocate_units?
  end

  def preview?
    update?
  end

  def verify?
    update?
  end

  # Permission only — whether notification can actually be sent right now (call approved,
  # send flag on, doc-gen not skipped, recipients exist) is surfaced separately via
  # CapitalRemittance#notification_blocked_reasons so the UI can grey the action out with
  # an explanation instead of hiding it outright.
  def send_notification?
    update?
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
