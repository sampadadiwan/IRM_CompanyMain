class OfferCompanyAdminPolicy < SaleBasePolicy
  def matched_interests?
    # Get the interests this user can see as a buyer
    interest_ids = InterestPolicy::Scope.new(user, Interest).resolve.pluck(:id)
    # Check if this record is allocated to any of those interests
    record.allocations.verified.exists?(interest_id: interest_ids)
  end

  def bulk_actions?
    user.enable_secondary_sale && permissioned_employee?(:update)
  end

  def index?
    user.enable_secondary_sale
  end

  def show?
    permissioned_employee?
  end

  def create?
    permissioned_employee?(:create) && record.secondary_sale.manage_offers
  end

  def approve?
    user.has_cached_role?(:approver) && permissioned_employee?(:update)
  end

  def generate_docs?
    permissioned_employee?(:update)
  end

  def accept_spa?
    permissioned_employee?(:update) && record.secondary_sale.manage_offers &&
      record.verified && !record.final_agreement
  end

  def new?
    create?
  end

  def update?
    create? && !record.verified
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
