class InvestmentInstrumentPolicy < ApplicationPolicy
  def index?
    user.entity.permissions.enable_fund_portfolios?
  end

  def report?
    update?
  end

  def show?
    user.entity.permissions.enable_fund_portfolios? &&
      belongs_to_entity?(user, record)
  end

  def create?
    # D: the parent is in one of the user's firms (funds_api_security_policy_plan.md)
    user.entity.permissions.enable_fund_portfolios? &&
      belongs_to_entity?(user, record) && parent_in_users_firms?(record.portfolio_company)
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

  def sub_categories?
    true
  end
end
