class AggregatePortfolioInvestmentPolicy < FundBasePolicy
  def index?
    true
  end

  def show?
    (user.enable_funds && permissioned_employee?) ||
      (record.fund.show_portfolios && permissioned_investor?)
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
