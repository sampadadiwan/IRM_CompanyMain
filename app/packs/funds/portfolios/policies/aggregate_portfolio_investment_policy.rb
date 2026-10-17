class AggregatePortfolioInvestmentPolicy < FundBasePolicy
  class Scope < FundBasePolicy::Scope
    def resolve
      if user.curr_role == "investor"
        # Investors only have AccessRights on the fund they actually
        # invest through (often a feeder fund), not on its master fund.
        # FeederMasterFundAccess bridges that gap by also including master
        # funds reached via a directly-accessible feeder fund -- see
        # app/packs/funds/portfolios/policies/feeder_master_fund_access.rb.
        # Filtering by a plain fund_id IN (...) here (rather than chaining
        # .or() between two relations) avoids ActiveRecord's structurally
        # compatible joins requirement for #or.
        scope.joins(:fund)
             .where(fund_id: FeederMasterFundAccess.eligible_ids_for_investor(user))
             .where("funds.features & ? > 0", Fund.features.maps[:show_portfolios])
             # Funds on an Allocated LP portfolio view show only the holdings allocated to this LP's folio
             # (H2, X17 — openspec/changes/lp-folio-portfolio-dashboard/business-rules.md)
             .then { |relation| LpPortfolioVisibility.for_user(user).restrict(relation) }
      else
        # Non-investors: use the standard role-based scope chain
        # (rm / company_admin / employee / super).
        super
      end
    end
  end

  def index?
    true
  end

  def show?
    (user.enable_funds && permissioned_employee?) ||
      (record.fund.features.show_portfolios? &&
        (
          # Direct case: investor has an AccessRight on this exact fund.
          FundPolicy.new(user, record.fund).permissioned_investor? ||
          # Bridge case: this is a master fund and the investor has an
          # AccessRight on one of its feeder funds instead. Without this,
          # a master-fund row that the index Scope shows would 403 the
          # moment the investor clicked into it.
          (user.curr_role == "investor" && FeederMasterFundAccess.accessible_to_investor?(user, record.fund))
        ) &&
        # X17 — a holding outside the LP's folio allocation is refused on a direct request too
        (user.curr_role != "investor" || LpPortfolioVisibility.for_user(user).api_visible?(record)))
  end

  def create?
    false
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

  def add_valuation?
    belongs_to_entity?(user, record)
  end

  def add_investment?
    belongs_to_entity?(user, record)
  end

  def destroy?
    belongs_to_entity?(user, record)
  end
end
