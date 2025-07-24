class OfferInvestorPolicy < SaleBasePolicy
  def matched_interests?
    # Get the interests this user can see as a buyer
    interest_ids = InterestPolicy::Scope.new(user, Interest).resolve.pluck(:id)
    # Check if this record is allocated to any of those interests
    record.allocations.verified.exists?(interest_id: interest_ids)
  end

  def bulk_actions?
    false
  end

  def index?
    user.enable_secondary_sale
  end

  def show?
    permissioned_investor?(:seller) || matched_interests?
  end

  def create?
    true
  end

  def approve?
    false
  end

  def generate_docs?
    false
  end

  def accept_spa?
    ((record.user_id == user.id) || (record.investor && record.investor.investor_entity_id == user.entity_id)) &&
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
