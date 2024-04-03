class InterestPolicy < SaleBasePolicy
  def index?
    user.enable_secondary_sale
  end

  def owner?
    (record && user.entity_id == record.interest_entity_id) || support?
  end

  def matched_offer?
    Offer.where(interest_id: record.id, user_id: user.id).present?
  end

  def show?
    (user.entity_id == record.interest_entity_id) ||
      belongs_to_entity?(user, record) ||
      sale_policy.owner? ||
      owner? ||
      matched_offer? # The matched offers user can see the interest
  end

  def short_list?
    user.has_cached_role?(:approver) && belongs_to_entity?(user, record)
  end

  def unscramble?
    (record.escrow_deposited? && belongs_to_entity?(user, record)) || # Escrow is deposited
      user.entity_id == record.interest_entity_id || # Interest is by this entity
      permissioned_investor?(:seller) # Is a seller added by the company for this sale
  end

  def create?
    user.id == record.user_id
  end

  def new?
    user.id == record.user_id
  end

  def update?
    (create? || support? ||
      user.entity_id == record.interest_entity_id ||
     (sale_policy.update? && record.secondary_sale.manage_interests)
    ) && !record.finalized
  end

  def accept_spa?
    update? && record.short_listed && !record.final_agreement
  end

  def matched_offers?
    create? ||
      sale_policy.owner? ||
      owner?
  end

  def edit?
    update?
  end

  def finalize?
    update? && record.short_listed
  end

  def destroy?
    update?
  end

  def allocation_form?
    sale_policy.update?
  end

  def allocate?
    sale_policy.update?
  end

  def sale_policy
    @sale_policy ||= SecondarySalePolicy.new(user, record.secondary_sale)
    @sale_policy
  end
end
