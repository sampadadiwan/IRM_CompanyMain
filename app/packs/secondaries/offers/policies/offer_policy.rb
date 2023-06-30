class OfferPolicy < SaleBasePolicy
  def index?
    user.enable_secondary_sale
  end

  def show?
    create? ||
      belongs_to_entity?(user, record) ||
      sale_policy.owner? ||
      interest_policy.owner? || super_user?
  end

  def create?
    if belongs_to_entity?(user, record)
      record.secondary_sale.manage_offers

    elsif user.has_cached_role?(:investor)
      record.holding.investor.investor_entity_id == user.entity_id

    elsif user.has_cached_role?(:holding)
      record.holding.user_id == user.id && record.holding.entity_id == record.entity_id

    else
      false
    end
  end

  def approve?
    user.has_cached_role?(:approver) && belongs_to_entity?(user, record)
  end

  def accept_spa?
    ((record.holding.user_id == user.id) ||
    (record.investor && record.investor.investor_entity_id == user.entity_id) ||
     (belongs_to_entity?(user, record) && record.secondary_sale.manage_offers)) &&
      (record.verified && !record.final_agreement)
  end

  def new?
    create?
  end

  def update?
    (create? || super_user?) && !record.verified # && !record.secondary_sale.lock_allocations
  end

  def allocation_form?
    sale_policy.owner?
  end

  def allocate?
    sale_policy.owner?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end

  def sale_policy
    @sale_policy ||= SecondarySalePolicy.new(user, record.secondary_sale)
    @sale_policy
  end

  def interest_policy
    @interest_policy ||= InterestPolicy.new(user, record.interest)
    @interest_policy
  end
end
