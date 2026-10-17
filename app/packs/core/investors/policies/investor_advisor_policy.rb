class InvestorAdvisorPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    # Finding 4: Ensure the feature flag is checked.
    user.enable_investor_advisors && !user.investor_advisor?
  end

  def show?
    index? && belongs_to_entity?(user, record)
  end

  def create?
    # Finding 4: Feature flag must be enforced for write operations, not just index.
    # Also restricted to company_admin to prevent regular employees from creating advisors.
    user.enable_investor_advisors &&
      belongs_to_entity?(user, record) &&
      user.has_cached_role?(:company_admin)
  end

  def switch?
    user.has_cached_role?(:investor_advisor) && record.user_id == user.id
  end

  def new?
    create?
  end

  def new_for_investor?
    investor = record[:investor]
    return false if investor.nil?

    # Finding 1: Check that the current user belongs to the managing entity
    # of the investor. This prevents IDOR where a user from one entity
    # could add an advisor to an investor belonging to another entity.
    belongs_to_entity?(user, investor) && user.has_cached_role?(:company_admin) &&
      fund_of_investors_company?(record[:fund], investor)
  end

  def create_for_investor?
    investor = record[:investor]
    return false if investor.nil?

    # Finding 1: Same IDOR protection as new_for_investor?.
    belongs_to_entity?(user, investor) && user.has_cached_role?(:company_admin) &&
      fund_of_investors_company?(record[:fund], investor)
  end

  # The fund the advisor is granted must be one of the investor's fund company. fund_id comes from
  # the request, and AddFolioInvestorAdvisor writes an AccessRight on whatever fund it is given, so
  # without this an admin could grant an advisor any other tenant's fund.
  # nil = a caller that names no fund (the not-found branches), which are judged as before.
  # Worked examples S2, S2-H — openspec/changes/fix-tenant-isolation-batch1/report.md#verification
  def fund_of_investors_company?(fund, investor)
    fund.nil? || fund.entity_id == investor.entity_id
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
end
