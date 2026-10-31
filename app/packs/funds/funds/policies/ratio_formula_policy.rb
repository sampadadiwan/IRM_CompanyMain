class RatioFormulaPolicy < FundBasePolicy
  # H18 — ratio formulas are staff-only records: no LP screen, mobile endpoint or MCP answer is meant to list
  # them. FundBasePolicy's investor branch would list every one in a fund the LP can see, so an investor
  # persona (an LP, an advisor switched to investor) gets none. The RM branch is FundBasePolicy's, unchanged.
  # Tests H18-6 — features/security/lp_staff_only_fund_lists.feature
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

  # H18 — the fund's own staff (and support) only. index? alone let any funds-enabled user, of any firm,
  # open any fund's formula (RatioFormulasController#set_fund finds the fund unscoped). Test H18-7 —
  # features/security/lp_staff_only_fund_lists.feature
  def show?
    permissioned_employee?
  end

  def create?
    user.enable_funds && permissioned_employee?(:create)
  end

  def new?
    create?
  end

  def update?
    user.enable_funds && permissioned_employee?(:update)
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end

  def import?
    user.enable_funds && permissioned_employee?(:create)
  end
end
