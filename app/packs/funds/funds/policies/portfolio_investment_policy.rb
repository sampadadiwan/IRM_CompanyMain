class PortfolioInvestmentPolicy < FundBasePolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:company_admin) && user.entity_type == "Investment Fund"
        scope.where(entity_id: user.entity_id)
      elsif user.curr_role == 'employee' && user.entity_type == "Investment Fund"
        scope.for_employee(user)
      elsif user.entity_type == "Group Company"
        scope.for_parent_employee(user)
      else
        scope.for_investor(user)
      end
    end
  end

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
    false
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

  def sub_categories?
    true
  end
end
