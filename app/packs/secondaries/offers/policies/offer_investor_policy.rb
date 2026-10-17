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

  # Only the seller's own offer, and only before it is verified (S5). create? is true for any
  # investor (anyone may make an offer), so `create? && !verified` let any investor-persona user
  # edit or delete someone else's unverified offer - PAN and bank details included. "Own" is the
  # same test accept_spa? uses: the offer's user, or a user of the offering investor.
  # Worked example S5 — openspec/changes/fix-tenant-isolation-batch1/report.md#verification
  def update?
    own_offer? && !record.verified
  end

  def own_offer?
    record.user_id == user.id || (record.investor.present? && record.investor.investor_entity_id == user.entity_id)
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
