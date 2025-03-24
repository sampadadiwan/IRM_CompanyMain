class FundPolicy < FundBasePolicy
  def index?
    user.enable_funds
  end

  def report?
    show?
  end

  def generate_reports?
    update?
  end

  def allocate?
    update?
  end

  def copy_formulas?
    update? && support?
  end

  def allocate_form?
    update?
  end

  def export?
    update?
  end

  def check_access_rights?
    update?
  end

  def generate_documentation?
    update?
  end

  def show?
    user.enable_funds &&
      (
        permissioned_employee? ||
        permissioned_investor?
      )
  end

  # rubocop:disable Style/RedundantCondition
  def dashboard?
    if permissioned_employee?
      true
    else
      # He is an investor, so can see the portfolio only if show_portfolios is true
      (record.show_portfolios && permissioned_investor?) ||
        # He can see the feeder fund
        if record.feeder_funds.present?
          allowed = false
          record.feeder_funds.each do |feeder_fund|
            allowed = FundPolicy.new(user, feeder_fund).dashboard?
            break if allowed
          end
          allowed
        else
          false
        end
    end
  end
  # rubocop:enable Style/RedundantCondition

  def generate_tracking_numbers?
    record.has_tracking_currency? && update?
  end

  def generate_fund_ratios?
    update?
  end

  def last?
    update?
  end

  def create?
    user.enable_funds &&
      permissioned_employee?(:create)
  end

  def new?
    create?
  end

  def update?
    user.enable_funds &&
      permissioned_employee?(:update)
  end

  def edit?
    update?
  end

  def delete_all?
    user.has_cached_role?(:company_admin) && permissioned_employee?(:update)
  end

  def destroy?
    Rails.env.test? ? permissioned_employee?(:destroy) : support?
  end
end
