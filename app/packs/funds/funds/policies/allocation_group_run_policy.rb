# Run history is visible to company admins and to employees permissioned on every fund the
# run touched. Runs are never edited from the UI — lock/unlock stay on the allocation runs.
class AllocationGroupRunPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.curr_role == "investor"
        scope.none
      else
        scope.where(entity_id: user.entity_id)
      end
    end
  end

  def index?
    user.enable_funds && !user.curr_role_investor?
  end

  def show?
    return false unless index?
    return false unless belongs_to_entity?(user, record)
    return true if user.has_cached_role?(:company_admin)

    funds = Fund.where(id: record.items.map(&:fund_id).uniq)
    funds.all? { |fund| FundPolicy.new(user, fund).allocate? }
  end
end
