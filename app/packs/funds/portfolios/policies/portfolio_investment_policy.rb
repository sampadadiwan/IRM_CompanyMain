class PortfolioInvestmentPolicy < FundBasePolicy
  def index?
    true
  end

  def show?
    user.enable_funds &&
      permissioned_employee?
  end

  def create?
    user.enable_funds &&
      permissioned_employee?
  end

  def new?
    create?
  end

  # No updates to investments as the current algorith for attribution cannot handle updates
  # So delete and create if you want to update
  def update?
    create?
  end

  def edit?
    update?
  end

  def destroy?
    # Buys cant be deleted easily as they may have been used up in sells
    # If they have portfolio_attributions associated with the buy, then cant delete it
    if record.buy? && record.buys_portfolio_attributions.count.positive?
      false
    else
      create?
    end
  end
end
