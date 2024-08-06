class CapitalCommitmentPolicy < FundBasePolicy
  def index?
    true
  end

  def report?
    update?
  end

  def show?
    permissioned_employee? ||
      permissioned_investor? || support?
  end

  def documents?
    true
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update) || support?
  end

  def transfer_fund_units?
    update?
  end

  def generate_documentation?
    update? && !record.esign_completed && record.investor_kyc&.verified
  end

  def generate_soa_form?
    generate_soa?
  end

  def generate_soa?
    update? && record.investor_kyc&.verified
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy) || support?
  end
end
