# Financial statements are for the fund team only (no investors, no advisors). Viewing and
# downloading need read access to the fund; generating, editing the mapping or layout and locking
# need update access. Records are scoped to the user's entity.
# Worked examples H20, X13, X14 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementBasePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      # X14: another entity's records are simply not found
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    show?
  end

  def show?
    # H20: read access to the fund is enough to view and download
    same_entity? && fund_policy.show?
  end

  def create?
    # X13: generating, editing and locking need update access (a read-only user is refused)
    same_entity? && fund_policy.update?
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end

  private

  def same_entity?
    record.entity_id == user.entity_id
  end

  def fund_policy
    Pundit.policy(user, record.fund)
  end
end
