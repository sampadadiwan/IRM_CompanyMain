class OfferPolicy < SaleBasePolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:company_admin) && ["Company", "Group Company"].include?(user.entity_type)
        scope.for_company_admin(user)
      elsif user.has_cached_role?(:employee) && ["Company", "Group Company"].include?(user.entity_type)
        scope.for_employee(user)
      # elsif user.curr_role == 'holding'
      #   scope.for_investor(user).distinct
      else
        user.entity.entity_type == "Holding" ? scope.where(user_id: user.id) : scope.for_investor(user)
      end
    end
  end

  def bulk_actions?
    support? || (user.enable_secondary_sale && user.has_cached_role?(:company_admin))
  end

  def index?
    user.enable_secondary_sale
  end

  def show?
    create? ||
      belongs_to_entity?(user, record) ||
      sale_policy.owner? ||
      interest_policy.owner?
  end

  def create?
    if belongs_to_entity?(user, record)
      record.secondary_sale.manage_offers

    elsif user.has_cached_role?(:investor) && record.holding.present?
      record.holding.investor.investor_entity_id == user.entity_id

    elsif user.has_cached_role?(:holding) && record.holding.present?
      record.holding.user_id == user.id && record.holding.entity_id == record.entity_id
    end
  end

  def approve?
    user.has_cached_role?(:approver) && belongs_to_entity?(user, record)
  end

  def generate_docs?
    belongs_to_entity?(user, record)
  end

  def accept_spa?
    ((record.user_id == user.id) ||
    (record.investor && record.investor.investor_entity_id == user.entity_id) ||
     (belongs_to_entity?(user, record) && record.secondary_sale.manage_offers)) &&
      (record.verified && !record.final_agreement)
  end

  def new?
    create?
  end

  def update?
    (support? ||
    (belongs_to_entity?(user, record) && record.secondary_sale.manage_offers) ||
    record.user_id == user.id) && !record.verified # && !record.secondary_sale.lock_allocations
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
