class DealInvestorPolicy < DealBasePolicy
  class Scope < Scope
    def resolve
      if user.entity_type == "Group Company"
        scope.where(entity_id: user.entity.child_ids)
      elsif %w[employee].include?(user.curr_role) && user.has_cached_role?(:company_admin)
        scope.where(entity_id: user.entity_id)
      elsif %w[employee].include? user.curr_role
        # find all deals that user has access to
        deal_ids = Deal.for_employee(user).includes(:access_rights).where("access_rights.user_id=?", user.id).pluck(:id)
        # find all deal investors that are associated with the deals
        scope.where(entity_id: user.entity_id, deal_id: deal_ids).or(scope.for_employee(user))
      elsif user.curr_role == "investor"
        scope.for_investor(user)
      end
    end
  end

  def index?
    true
  end

  def show?
    (user.entity_id == record.investor_entity_id) ||
      permissioned_employee?
  end

  def create?
    belongs_to_entity?(user, record) && DealPolicy.new(user, record.deal).update?
  end

  def new?
    create?
  end

  def update?
    create? ||
      permissioned_employee?(:update)
  end

  def edit?
    update?
  end

  def destroy?
    create? ||
      permissioned_employee?(:destroy)
  end

  def permissioned_employee?(perm = nil)
    return support? unless belongs_to_entity?(user, record)

    if user.has_cached_role?(:company_admin)
      true
    else
      @deal ||= Deal.includes(:access_rights).find_by(id: record.deal_id)
      val = if perm
              @deal.present? && @deal.access_rights[0].permissions.set?(perm)
            else
              @deal.present?
            end
      return val if val

      @deal_investor ||= DealInvestor.for_employee(user).includes(:access_rights).find_by(id: record.id)
      if perm
        @deal_investor.present? && @deal_investor.access_rights[0].permissions.set?(perm)
      else
        @deal_investor.present?
      end
    end
  end
end
