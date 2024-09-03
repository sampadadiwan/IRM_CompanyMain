class CapitalCommitmentPolicy < FundBasePolicy
  def index?
    user.enable_funds
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

  def documents?
    true
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update)
  end

  def transfer_fund_units?
    update?
  end

  def generate_documentation?
    record.investor_kyc&.verified && update? && !record.esign_completed
  end

  def generate_soa_form?
    generate_soa?
  end

  def generate_soa?
    record.investor_kyc&.verified && update?
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy) || (permissioned_employee? && support?)
  end
end
