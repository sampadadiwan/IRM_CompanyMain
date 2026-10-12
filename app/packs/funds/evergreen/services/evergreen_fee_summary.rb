# Figures for the Fees tab, per class: management-fee accruals and the payable on each approved NAV,
# and the performance fee's high-water mark, distance from NAV per unit and crystallisations.
# Worked examples H28, E38 — openspec/changes/open-ended-funds/design.md#worked-examples
class EvergreenFeeSummary
  Row = Data.define(:unit_type, :fee_pct, :navs, :nav_rows, :hwm_cents, :latest_nav, :crystallisations, :perf_fee_pct)

  # One NAV's management-fee working: previous payable + accrued − paid = payable.
  # accrued_cents / paid_cents are nil for a NAV drafted before the builder saved them (or an uploaded one).
  # state: :accrued, :partial (accrued only to an earlier date), :missing, :uploaded, :no_fee or :no_units
  # locked_by: the dealing date priced at this NAV, which blocks reopening it
  # late_included / late_excluded: late fees decided on this NAV (R9.13); late_booked: fee entries booked into this
  # NAV's period after it was approved and not yet decided anywhere (R9.12) — with reopen_ok when no dealing
  # date was priced at it (R9.16). evergreen-late-management-fees ⑦
  NavRow = Data.define(:nav, :opening_cents, :accrued_cents, :paid_cents, :state, :locked_by, :late_included_cents,
                       :late_excluded_cents, :late_booked, :reopen_ok)

  SHOWN = 12

  def initialize(fund)
    @fund = fund
  end

  def rows
    @fund.unit_types_list.map do |ut|
      # One more than shown, so the oldest row shown also has its previous payable
      fetched = FundNav.approved.where(fund_id: @fund.id, unit_type: ut).order(nav_date: :desc).limit(SHOWN + 1).to_a
      navs = fetched.first(SHOWN)
      latest = navs.first
      fee_pct = @fund.fund_unit_settings.find_by(name: ut)&.management_fee.to_d
      hwm, = NavInputs.new(@fund, (latest&.nav_date || Time.zone.today) + 1.day).high_water_mark(ut)
      term = @fund.evergreen_class_terms.find_by(unit_type: ut)
      # Late fees still undecided: the periods they sit in, worked out once for the class (sums only)
      late = latest ? EvergreenLateFees.call(@fund, ut, latest.nav_date + 1.day) : nil
      Row.new(unit_type: ut, fee_pct:, navs:, nav_rows: nav_rows(fetched, fee_pct, late), hwm_cents: hwm, latest_nav: latest,
              crystallisations: navs.select(&:crystallised), perf_fee_pct: term&.perf_fee_model == "class_hwm" ? term.perf_fee_pct : nil)
    end
  end

  private

  def nav_rows(fetched, fee_pct, late)
    navs = fetched.first(SHOWN)
    locks = dealing_locks(navs.map(&:id))
    navs.each_with_index.map do |nav, i|
      # The previous approved NAV's payable; a class's first NAV starts from nothing owed
      opening = fetched[i + 1]&.mgmt_fee_payable_cents.to_d
      saved = nav.breakdown.to_h
      booked = late&.outstanding_cents&.positive? && late.periods.include?(nav)
      NavRow.new(nav:, opening_cents: opening, accrued_cents: saved["mgmt_fee_accrued_cents"]&.to_d,
                 paid_cents: saved["mgmt_fee_paid_cents"]&.to_d, state: state_of(nav, fee_pct), locked_by: locks[nav.id],
                 late_included_cents: nav.late_included_cents, late_excluded_cents: nav.late_excluded_cents,
                 late_booked: booked || false, reopen_ok: booked && late.reopenable.include?(nav))
    end
  end

  # Same tests as evergreen_mgmt_fee_warning (E35, E36, review fix 4b), as a state for the row's badge
  def state_of(nav, fee_pct)
    return :uploaded if nav.uploaded?
    return :no_fee unless fee_pct.positive?
    # F8: nothing to charge a fee on yet (a class's first NAV, at its initial price)
    return :no_units unless nav.units_outstanding.to_d.positive?

    accrued_to = nav.mgmt_fee_accrued_to
    return :missing unless accrued_to

    accrued_to >= nav.nav_date ? :accrued : :partial
  end

  # The earliest dealing date priced at each NAV, in one query (X9: a NAV used by dealing can't be reopened)
  def dealing_locks(nav_ids)
    first_dates = DealingFill.where(fund_nav_id: nav_ids).joins(:dealing_date)
                             .group(:fund_nav_id).minimum("dealing_dates.date")
    dates = DealingDate.where(fund_id: @fund.id, date: first_dates.values.uniq).index_by(&:date)
    first_dates.transform_values { |date| dates[date] }
  end
end
