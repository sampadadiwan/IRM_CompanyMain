class AggregatePortfolioInvestmentPolicy < FundBasePolicy
  class Scope < FundBasePolicy::Scope
    def resolve
      if user.curr_role == "investor"
        super.joins(:fund).where("funds.show_portfolios = true")
      else
        super
      end
    end
  end

  def index?
    true
  end

  def show?
    (user.enable_funds && permissioned_employee?) ||
      (record.fund.show_portfolios && permissioned_investor?)
  end

  def toggle_show_portfolio?
    index?
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
