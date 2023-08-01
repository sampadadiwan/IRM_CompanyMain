class AggregatePortfolioInvestmentPolicy < FundBasePolicy
  def index?
    true
  end

  def show?
    user.enable_funds &&

      permissioned_employee?
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

  def destroy?
    belongs_to_entity?(user, record)
  end
end
