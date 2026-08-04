class FundUnitPolicy < FundBasePolicy
  class Scope < FundBasePolicy::Scope
    def resolve
      if user.curr_role == "investor"
        super.joins(:fund).where("funds.show_fund_units = true")
      else
        super
      end
    end
  end

  def index?
    user.enable_funds
  end

  def bulk_actions?
    index?
  end

  def show?
    permissioned_employee? ||
      (record.fund.show_fund_units && permissioned_investor?)
  end

  def create?
    permissioned_employee?(:create)
  end

  def new?
    create?
  end

  def verify?
    update?
  end

  def update?
    permissioned_employee?(:update)
  end

  def edit?
    update?
  end

  def generate_docs?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end
end
