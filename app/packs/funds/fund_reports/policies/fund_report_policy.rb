class FundReportPolicy < FundBasePolicy
  # H18 — fund reports are staff-only records: no LP screen, mobile endpoint or MCP answer is meant to list
  # them. FundBasePolicy's investor branch would list every one in a fund the LP can see, so an investor
  # persona (an LP, an advisor switched to investor) gets none. The RM branch is FundBasePolicy's, unchanged.
  # Tests H18-1 — features/security/lp_staff_only_fund_lists.feature
  class Scope < FundBasePolicy::Scope
    def resolve
      # Investor persona (but not an RM, who keeps FundBasePolicy's RM branch): nothing
      return scope.none if user.curr_role_investor? && !user.has_cached_role?(:rm)

      # Staff, RMs and support: FundBasePolicy's scope, as before
      super
    end
  end

  def index?
    user.enable_funds
  end

  def show?
    permissioned_employee?
  end

  def new?
    create?
  end

  def regenerate?
    create?
  end

  def download_page?
    create?
  end

  def create?
    permissioned_employee?(:create)
  end

  def update?
    permissioned_employee?(:update)
  end

  def destroy?
    create?
  end
end
