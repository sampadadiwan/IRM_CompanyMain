class CapitalCommitmentPolicy < FundBasePolicy
  def index?
    true
  end

  def report?
    update?
  end

  def show?
    permissioned_employee? ||
      permissioned_investor? || super_user?
  end

  def documents?
    true
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update) || super_user?
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
    permissioned_employee?(:destroy) || super_user?
  end
end
