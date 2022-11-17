class OfferPolicy < SaleBasePolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.curr_role == "advisor"
        scope.for_advisor(user)
      elsif user.curr_role.to_sym == :holding
        scope.where(user_id: user.id)
      elsif user.curr_role.to_sym == :investor
        scope.joins(:investor).where('investors.investor_entity_id': user.entity_id)
      elsif user.curr_role.to_sym == :secondary_buyer
        scope.joins(:interest).where("interests.interest_entity_id=?", user.entity_id)
      else
        scope.where(entity_id: user.entity_id)
      end
    end
  end

  def index?
    true
  end

  def show?
    create? ||
      (record.interest && record.interest.interest_entity_id == user.entity_id) ||
      sale_policy.owner? ||
      interest_policy.owner?
  end

  def create?
    if user.entity_id == record.entity_id
      true
    elsif user.has_cached_role?(:holding)
      record.holding.user_id == user.id && record.holding.entity_id == record.entity_id
    elsif user.has_cached_role?(:investor)
      record.holding.investor.investor_entity_id == user.entity_id
    else
      false
    end
  end

  def approve?
    user.has_cached_role?(:approver) && (user.entity_id == record.entity_id)
  end

  def accept_spa?
    ((record.holding.user_id == user.id) ||
     (user.entity_id == record.entity_id && record.secondary_sale.manage_offers)) &&
      (record.verified && !record.final_agreement)
  end

  def new?
    create?
  end

  def update?
    (
      (user.id == record.user_id) ||
      (sale_policy.update? && record.secondary_sale.manage_offers) # && !record.approved
    ) && !record.verified # && !record.secondary_sale.lock_allocations
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
