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
      else
        # Any other persona sees none (was nil, which broke callers chaining on the scope).
        scope.none
      end
    end
  end

  def index?
    true
  end

  # An advisor switched into a client needs a personal grant on the deal, as the deal investor list
  # (for_investor) already requires (B4-3). Plain investors keep the entity match: some deal
  # investors exist without a deal access right, and their own users must still open them.
  # Worked example B4-3 — openspec/changes/fix-tenant-isolation-batch2/report.md#verification
  def show?
    investor_side = if user.has_cached_role?(:investor_advisor) && !advisor_at_home?
                      permissioned_investor?
                    else
                      user.entity_id == record.investor_entity_id
                    end
    investor_side || permissioned_employee? || support?
  end

  def create?
    deal_update_permission = if record.deal.present?
                               # D: the investor is the deal firm's too
                               DealPolicy.new(user, record.deal).update? && parent_in_users_firms?(record.investor)
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
