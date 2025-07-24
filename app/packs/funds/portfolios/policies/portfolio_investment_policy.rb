class PortfolioInvestmentPolicy < FundBasePolicy
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
      (record.fund.show_portfolios && FundPolicy.new(user, record.fund).permissioned_investor?)
  end

  def create?
    user.enable_funds &&
      permissioned_employee?(:update) # Only employees with update permission on the fund can create investments
  end

  def new?
    create?
  end

  def base_amount_form?
    true
  end

  # No updates to investments as the current algorith for attribution cannot handle updates
  # So delete and create if you want to update
  def update?
    permissioned_employee?(:update)
  end

  def edit?
    update?
  end

  def destroy?
    # Buys cant be deleted easily as they may have been used up in sells
    # If they have portfolio_attributions associated with the buy, then cant delete it
    if record.buy? && record.buys_portfolio_attributions.any?
      false
    else
      permissioned_employee?(:destroy)
    end
  end

  def conversion?
    record.buy? && record.net_quantity.positive?
  end
end
