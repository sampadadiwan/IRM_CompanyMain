class InterestRmPolicy < SaleBasePolicy
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
    (permissioned_rm? || matched_offer?) && rm_mapping.permissions.read?
  end

  def generate_docs?
    permissioned_rm? && record.short_listed && rm_mapping.permissions.generate_docs?
  end

  def short_list?
    permissioned_rm? && rm_mapping.permissions.update? && record.short_listed_status == Interest::STATUS_PENDING
  end

  def send_email_to_change?
    !update?
  end

  def create?
    permissioned_rm? && rm_mapping.permissions.create?
  end

  def new?
    permissioned_rm?
  end

  def update?
    permissioned_rm? && !record.verified && rm_mapping.permissions.update?
  end

  def accept_spa?
    permissioned_rm? && record.verified
  end

  def matched_offers?
    permissioned_rm?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
