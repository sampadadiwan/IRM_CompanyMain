class DealInvestorPolicy < DealBasePolicy
  class Scope < Scope
    def resolve
      if user.entity_type == "Group Company"
        scope.where(entity_id: user.entity.child_ids)
      elsif %w[employee].include?(user.curr_role) && user.has_cached_role?(:company_admin)
        scope.where(entity_id: user.entity_id)
      elsif %w[employee].include? user.curr_role
        scope.for_employee(user)
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
end
