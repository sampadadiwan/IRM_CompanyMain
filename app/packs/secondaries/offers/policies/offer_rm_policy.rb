class OfferRmPolicy < SaleBasePolicy
  def matched_interests?
    # Get the interests this user can see as a buyer
    interest_ids = InterestPolicy::Scope.new(user, Interest).resolve.pluck(:id)
    # Check if this record is allocated to any of those interests
    record.allocations.verified.exists?(interest_id: interest_ids)
  end

  def bulk_actions?
    user.enable_secondary_sale && permissioned_rm?(:update)
  end

  def index?
    user.enable_secondary_sale
  end

  def show?
    (permissioned_rm? || matched_interests?) && rm_mapping.permissions.read?
  end

  def create?
    permissioned_rm? && rm_mapping.permissions.create?
  end

  def approve?
    permissioned_rm? && rm_mapping.permissions.approve?
  end

  def generate_docs?
    update? && rm_mapping.permissions.generate_docs?
  end

  def accept_spa?
    permissioned_rm? &&
      record.verified && !record.final_agreement && rm_mapping.permissions.update?
  end

  def new?
    permissioned_rm?
  end

  def update?
    permissioned_rm? && !record.verified && rm_mapping.permissions.update?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
