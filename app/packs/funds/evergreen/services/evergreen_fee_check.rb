# Is a NAV's management fee accrued up to its date? One rule for the NAV page's message, the
# "fee accrual behind" alert and the approval refusal (R9.2), so the three never disagree.
# Worked examples H108, E342, E343, E344, E345, X208 —
# openspec/changes/archive/2026-10-11-evergreen-late-management-fees/design.md#worked-examples
module EvergreenFeeCheck
  module_function

  # No fee is due, so nothing is checked
  def exempt?(fund_nav)
    # E343: an uploaded NAV is the administrator's figure, fee included (review fix 4b)
    return true if fund_nav.uploaded?
    # E344: no units outstanding (a class's first NAV) — nothing to charge a fee on (F8)
    return true unless fund_nav.units_outstanding.to_d.positive?

    # E342: the class charges no management fee
    !fee_pct(fund_nav).positive?
  end

  # Why the fee isn't accrued up to the NAV date, or nil when it is (or the NAV is exempt).
  # X208: this message refuses approval of a draft; H108 / E345: accrued on or after the NAV date passes
  def accrual_message(fund_nav)
    return nil if exempt?(fund_nav)

    accrued_to = fund_nav.mgmt_fee_accrued_to
    return nil if accrued_to && accrued_to >= fund_nav.nav_date

    # An approved NAV can't be approved again — it is reopened to take the fee in
    next_step = fund_nav.approved? ? "and reopen this NAV to include it" : "then recalculate"
    run_to = "run the fee formula to #{I18n.l(fund_nav.nav_date, format: :day_month_year)}, #{next_step}"
    return "No management fee accrued yet — #{run_to}" unless accrued_to

    "Management fee accrued only to #{I18n.l(accrued_to, format: :day_month_year)} — #{run_to}"
  end

  def fee_pct(fund_nav)
    fund_nav.fund.fund_unit_settings.find_by(name: fund_nav.unit_type)&.management_fee.to_d
  end
end
