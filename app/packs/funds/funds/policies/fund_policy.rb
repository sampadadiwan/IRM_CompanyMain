class FundPolicy < FundBasePolicy
  def index?
    user.enable_funds
  end

  # The fund-wide report pages (advisor payouts, sign-in counts, onboarding, calls, remittances) and
  # report generation are for the fund's own staff (S6). show? also admits permissioned LPs, and
  # FundsController#report renders any funds/ template, so LPs could read every investor's data.
  # Every link to these reports already sits in the staff-only part of the fund page.
  # Worked example S6 — openspec/changes/fix-tenant-isolation-batch1/report.md#verification
  def report?
    show? && permissioned_employee?
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

  # funds-json-api-hardening P6 H27 X30: recomputing totals changes stored figures — those who can edit the fund
  def recompute_totals?
    update?
  end

  # funds-json-api-hardening ⑦ H8 X23: the fund summary is the fund page's own figures — same access
  def summary?
    show?
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
      (record.features.show_portfolios? && permissioned_investor?) ||
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

  # Force regeneration recomputes every tracking amount of the fund, not only the unfilled ones.
  # It used to be offered to anyone who added ?debug=true to the fund page URL; it is a support
  # tool, like the tracking currency change it is the manual half of.
  def force_generate_tracking_numbers?
    generate_tracking_numbers? && support?
  end

  # Changing the tracking currency once a fund exists rewrites every stored tracking amount at
  # historical rates (ChangeTrackingCurrencyJob), needs a complete rate history for the new pair,
  # and restates figures investors may already have been sent in the old currency - so only
  # support may do it, and only through that job. The fund edit form's field is locked for
  # everyone after creation, support included (FundsController#update refuses the change).
  def change_tracking_currency?
    update? && support?
  end

  def retry_tracking_currency_change?
    change_tracking_currency?
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
