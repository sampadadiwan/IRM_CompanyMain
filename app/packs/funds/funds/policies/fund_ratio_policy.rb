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
    user.enable_funds
  end

  def show?
    permissioned_employee? ||
      # fund_id is nil for cross-fund/cross-portfolio rows — skip investor check.
      (record.fund.present? && record.fund.show_fund_ratios && FundPolicy.new(user, record.fund).permissioned_investor?)
  end

  def create?
    false
  end

  def generate?
    true
  end

  def new?
    create?
  end

  def update?
    (record.fund.present? && FundPolicy.new(user, record.fund).create? && record.import_upload_id.present?) || support?
  end

  def edit?
    update?
  end

  def destroy?
    record.fund.present? && FundPolicy.new(user, record.fund).create?
  end
end
