class FundPolicy < FundBasePolicy
  def index?
    user.enable_funds
  end

  def report?
    show?
  end

  # Cross-folio aggregate data (Account Entries Period Report, fund-level) - employees only,
  # unlike report?/show? which also admit permissioned investors for single-fund views.
  def period_report?
    user.enable_funds && permissioned_employee?
  end

  def generate_reports?
    update?
  end

  def allocate?
    update?
  end

  def trigger_adhoc_notification?
    update?
  end

  # Destination-fund gate for copying formulas INTO this fund. Requires update rights on the
  # destination (any user who may edit this fund). Cross-entity behaviour is enforced separately
  # on the SOURCE fund in FundsController#copy_formulas via `authorize from_fund, :show?`:
  #   - regular users can only copy from a fund in their own entity (same-entity), and
  #   - support users may copy cross-entity (the accepted support fallthrough — see H1/H5).
  # (Previously this was `update? && support?`, which blocked regular users from copying at all.)
  def copy_formulas?
    update?
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

  def analytics?
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
    record.entity.permissions.set?(:enable_tracking_currency) && update?
  end

  # Tracking currency is locked after fund creation for regular users, because changing it
  # requires safely reprocessing account entries/tracking amounts (see TrackingCurrencyJob) -
  # only support may correct a bad value post-creation. (Replaces the old unauthenticated
  # ?debug=true escape hatch on the fund edit form, which any user with edit access could use.)
  def update_tracking_currency?
    update? && support?
  end

  def generate_fund_ratios?
    update?
  end

  def last?
    update?
  end

  def create?
    user.enable_funds &&
      permissioned_employee?(:create) && !record.snapshot
  end

  def new?
    create?
  end

  def update?
    user.enable_funds &&
      permissioned_employee?(:update) && !record.snapshot
  end

  def edit?
    update?
  end

  def show_email_list?
    update?
  end

  def delete_all?
    user.has_cached_role?(:company_admin) && permissioned_employee?(:update)
  end

  def destroy?
    Rails.env.test? ? permissioned_employee?(:destroy) : support?
  end

  def run_agent?
    permissioned_employee?(:update)
  end
end
