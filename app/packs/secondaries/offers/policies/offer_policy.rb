class OfferPolicy < SaleBasePolicy
  class Scope < Scope
    def resolve
      case user.curr_role.to_sym
      when :employee
        user.has_cached_role?(:company_admin) ? scope.where(entity_id: user.entity_id) : scope.for_employee(user)
      when :holding
        scope.where(user_id: user.id)
      when :investor
        scope.for_investor(user)
      else
        scope.none
      end
    end
  end

  def index?
    user.enable_secondary_sale
  end

  def show?
    create? ||
      user.entity_id == record.entity_id ||
      sale_policy.owner? ||
      interest_policy.owner? || super_user?
  end

  def create?
    if user.entity_id == record.entity_id
      record.secondary_sale.manage_offers
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

  def generate_esign_link?
    record.entity_id == user.entity_id &&
      record.signatory_ids(:adhaar).present? &&
      record.esigns.count.zero?
  end

  def esign?
    record.spa.present? &&
      record.signatory_ids(:adhaar).include?(user.id) &&
      record.esign_required &&
      !record.esign_completed
  end
end
