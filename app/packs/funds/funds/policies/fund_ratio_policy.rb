class FundRatioPolicy < FundBasePolicy
  class Scope < FundBasePolicy::Scope
    def resolve
      if user.curr_role == "investor"
        super.joins(:fund).where("funds.show_fund_ratios = true")
      else
        super
      end
    end
  end

  def index?
    true
  end

  def show?
    belongs_to_entity?(user, record) ||
      (record.fund.show_fund_ratios && permissioned_investor?)
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
    update?
  end
end
