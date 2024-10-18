class InterestInvestorPolicy < SaleBasePolicy
  def index?
    user.enable_secondary_sale
  end

  def owner?
    record && user.entity_id == record.interest_entity_id
  end

  def matched_offer?
    # Get the offers this user can see as a buyer
    offer_ids = OfferPolicy::Scope.new(user, Offer).resolve.pluck(:id)
    # Check if this record is allocated to any of those interests
    record.allocations.verified.exists?(offer_id: offer_ids)
  end

  def show?
    permissioned_investor?(:buyer) || matched_offer? # The matched offers user can see the interest
  end

  def generate_docs?
    false
  end

  def short_list?
    permissioned_investor?(:buyer) && record.short_listed_status == Interest::STATUS_PENDING
  end

  def create?
    permissioned_investor?(:buyer)
  end

  def new?
    create?
  end

  def update?
    permissioned_investor?(:buyer) && !record.verified
  end

  def accept_spa?
    permissioned_investor?(:buyer) && record.verified
  end

  def matched_offers?
    true
  end

  def edit?
    update?
  end

  def destroy?
    false
  end
end
