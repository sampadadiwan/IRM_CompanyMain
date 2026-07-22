class DealInvestorPolicy < DealBasePolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:rm)
        scope.for_rm(user)
      elsif user.entity_type == "Group Company"
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
      permissioned_employee? || support?
  end

  def create?
    deal_update_permission = if record.deal.present?
                               DealPolicy.new(user, record.deal).update?
                             else
                               false
                             end
    (belongs_to_entity?(user, record) && deal_update_permission) ||
      deal_update_permission ||
      permissioned_rm?(:update) ||
      support?
  end

  def new?
    create?
  end

  def update?
    create? ||
      permissioned_employee?(:update) || support?
  end

  def edit?
    update?
  end

  def destroy?
    create? ||
      permissioned_employee?(:destroy) || support?
  end

  def permissioned_employee?(perm = nil)
    super
  end
end
