class OfferEmployeePolicy < SaleBasePolicy
  def matched_interests?
    # Get the interests this user can see as a buyer
    interest_ids = InterestPolicy::Scope.new(user, Interest).resolve.pluck(:id)
    # Check if this record is allocated to any of those interests
    record.allocations.verified.exists?(interest_id: interest_ids)
  end

  # H6 step 2 — class-safe: WithBulkActions authorizes the class (Offer), where there is no sale to
  # check access on (the record check used to raise on a class). On the class: secondaries enabled; on a
  # record (the job's per-row check): plus update access on the sale. Tests H6-H3, H6-S1…S3, H6-SH —
  # features/security/bulk_actions_authorization.feature
  def bulk_actions?
    return user.enable_secondary_sale if record.instance_of?(Class)

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
