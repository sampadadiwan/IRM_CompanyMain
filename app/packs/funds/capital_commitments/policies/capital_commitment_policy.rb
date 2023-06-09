class CapitalCommitmentPolicy < FundBasePolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:company_admin) && user.entity_type == "Investment Fund"
        scope.where(entity_id: user.entity_id)
      elsif user.curr_role == "employee" && user.entity_type == "Investment Fund"
        scope.for_employee(user)
      else
        scope.for_investor(user)
      end
    end
  end

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
    permissioned_employee?(:update)
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

  def generate_esign_link?
    update? &&
      record.signatory_ids(:adhaar).present? &&
      record.esigns.count.zero? && !record.esign_completed
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end

  def esign?
    record.signatory_ids(:adhaar).include?(user.id) && record.esign_required && !record.esign_completed
  end
end
