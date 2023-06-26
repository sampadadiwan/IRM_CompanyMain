class InvestmentPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.curr_role == "employee"
        scope.where(entity_id: user.entity_id)
      else
        scope.for_investor_all(user)
      end
    end
  end

  def index?
    user.enable_investments
  end

  def show?
    if (user.entity_id == record.entity_id && user.enable_investments) || super_user?
      true
    else
      user.enable_investments &&
        Investment.for_investor(user, record.entity)
                  .where("investments.id=?", record.id).first.present?
    end
  end

  def history?
    show?
  end

  def create?
    (user.entity_id == record.entity_id && user.enable_investments)
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    create? && !record.employee_holdings
  end

  def transfer?
    edit?
  end

  def convert?
    edit? && record.investment_instrument == "Preferred"
  end

  def destroy?
    create?
  end
end
