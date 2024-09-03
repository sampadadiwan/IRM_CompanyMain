class InterestPolicy < SaleBasePolicy
  def index?
    user.enable_secondary_sale
  end

  def owner?
    record && user.entity_id == record.interest_entity_id
  end

  def matched_offer?
    record.offers.where(user_id: user.id).present?
  end

  def show?
    permissioned_employee? ||
      owner? ||
      matched_offer? # The matched offers user can see the interest
  end

  def generate_docs?
    permissioned_employee?(:update) && record.short_listed
  end

  def short_list?
    permissioned_employee?(:update)
  end

  def unscramble?
    (record.escrow_deposited? && permissioned_employee?) || # Escrow is deposited
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
    (create? ||
      permissioned_investor?(:seller) ||
     (permissioned_employee?(:update) && record.secondary_sale.manage_interests)
    ) && !record.verified
  end

  def accept_spa?
    permissioned_investor?(:seller) && record.verified
  end

  def matched_offers?
    create? ||
      permissioned_employee? ||
      owner?
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:update) && !record.verified
  end

  def allocation_form?
    permissioned_employee?(:update)
  end

  def allocate?
    permissioned_employee?(:update)
  end

  def sale_policy
    @sale_policy ||= SecondarySalePolicy.new(user, record.secondary_sale)
    @sale_policy
  end
end
