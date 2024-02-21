class InvestmentInstrumentPolicy < ApplicationPolicy
  def index?
    user.entity.permissions.enable_fund_portfolios?
  end

  def report?
    update?
  end

  def show?
    (user.entity.permissions.enable_fund_portfolios? &&
    belongs_to_entity?(user, record)) || super_user?
  end

  def create?
    user.entity.permissions.enable_fund_portfolios? &&
      belongs_to_entity?(user, record)
  end

  def new?
    create?
  end

  def update?
    create? || super_user?
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
