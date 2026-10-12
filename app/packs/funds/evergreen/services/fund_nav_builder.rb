# Drafts one NAV per unit class for a date from CapHive data (design card ③).
#   fund-wide lines (fair value, cash, other assets, other liabilities) × the class share
#   class lines: management fee payable (rolling), performance fee payable (rolling) and accrued
#   NAV = assets − liabilities; NAV per unit = NAV ÷ units (initial price when no units)
# Re-drafting a date replaces its drafts but keeps their overrides; an approved NAV is never touched.
# Worked examples H3, H4, E7, E8, E35, E36, X5 — openspec/changes/open-ended-funds/design.md#worked-examples
class FundNavBuilder < Trailblazer::Operation
  step :check_dates
  step :gather_inputs
  step :build_navs

  def check_dates(ctx, fund:, nav_date:, **)
    unless fund.evergreen?
      ctx[:errors] = "This fund is not evergreen"
      return false
    end
    if FundNav.approved.exists?(fund_id: fund.id, nav_date:)
      ctx[:errors] = "An approved NAV exists for #{I18n.l(nav_date)} — reopen it to recalculate"
      return false
    end
    # Review fix 4a: drafting rebuilds EVERY class for the date and used to overwrite an uploaded draft
    # silently — the administrator's official figures replaced by CapHive's, with no warning. Now any
    # uploaded draft on the date blocks New NAV and Recalculate; delete it to draft from the ledger, or
    # upload again to correct it. Nothing is changed when refused.
    if (uploaded = FundNav.where(fund_id: fund.id, nav_date:, source: "uploaded").order(:unit_type).first)
      ctx[:errors] = "An uploaded NAV exists for Class #{uploaded.unit_type} on #{I18n.l(nav_date, format: :day_month_year)} " \
                     "— delete it to draft this date from the ledger"
      return false
    end
    true
  end

  def gather_inputs(ctx, fund:, nav_date:, **)
    inputs = NavInputs.new(fund, nav_date)
    # Reading fair value first surfaces a missing valuation before anything is written (X5)
    inputs.investments_fmv_cents
    ctx[:inputs] = inputs
  rescue NavInputs::MissingValuation => e
    ctx[:errors] = e.message
    false
  end

  def build_navs(ctx, fund:, nav_date:, inputs:, current_user: nil, **)
    unit_types = fund.unit_types_list
    # Fee payments go to the classes that owed them (decision 8 Oct 2026, E197–E200); any excess is
    # shared by value at the previous NAV, as before (E199, E200)
    @paid = fee_payments_by_class(inputs, unit_types, ClassApportioner.value_shares(inputs, unit_types))
    # Shared lines are split by each class's stake: what it owed is added back and what was paid for
    # it since comes off, so neither an unpaid fee nor its payment moves value between classes
    # (evergreen-share-classes H2, H3)
    # Class-only expenses and their payments since each class's previous NAV (H4, H5, E14–E21)
    @class_expenses = unit_types.index_with { |ut| class_expense_movements(inputs, ut) }
    paid_by_class = unit_types.index_with do |ut|
      @paid[:mgmt].fetch(ut, 0) + @paid[:perf].fetch(ut, 0) + @class_expenses[ut][:paid]
    end
    shares = ClassApportioner.shares(inputs, unit_types, paid: paid_by_class)
    # "Class …" ledger entries no class has claimed — warned on the NAV page, never silently dropped (E22, E23)
    @unclaimed = inputs.unclaimed_class_entries(unit_types.flat_map do |ut|
      term = inputs.setting.terms_for(ut)
      [term.class_expense_entry_name, term.class_expense_paid_entry_name]
    end)
    ctx[:fund_navs] = ActiveRecord::Base.transaction do
      unit_types.map { |ut| build_class_nav(fund, nav_date, ut, shares[ut], inputs, current_user) }
    end
    # Approvers (and Fund accounting when the fee lags) are told a NAV awaits approval (§ Notifications)
    ctx[:fund_navs].each { |nav| EvergreenAlerts.nav_drafted(nav) }
    true
  rescue ActiveRecord::RecordInvalid => e
    # X117: e.g. a negative NAV — nothing is saved (the transaction rolled back)
    ctx[:errors] = e.record.errors.full_messages.to_sentence
    false
  end

  private

  def build_class_nav(fund, nav_date, unit_type, share, inputs, user)
    setting = inputs.setting
    term = setting.terms_for(unit_type)
    prev = inputs.previous_nav(unit_type)
    prev_date = prev&.nav_date
    nav = FundNav.find_or_initialize_by(fund_id: fund.id, unit_type:, nav_date:)
    nav.assign_attributes(entity_id: fund.entity_id, status: "draft", source: "computed", prepared_by: user, class_share: share)

    # Fund-wide lines × the class share. Money for orders not yet dealt is taken out of the shared cash
    # first and given back to its own order's class, with an equal liability line — so it never moves
    # value between classes or into any class's NAV (E201–E203)
    dealing = inputs.dealing_in_progress_cents(unit_type)
    shared_cash = inputs.ledger_balance_cents(setting.cash_entry_name) - inputs.dealing_in_progress_total_cents
    nav.investments_fmv_cents = (inputs.investments_fmv_cents * share).round(2)
    nav.cash_cents = ((shared_cash * share) + dealing).round(2)
    nav.dealing_in_progress_cents = dealing.round(2)
    nav.other_assets_cents = (inputs.ledger_balance_cents(setting.other_assets_entry_name) * share).round(2)
    nav.other_liabilities_cents = (inputs.ledger_balance_cents(setting.other_liabilities_entry_name) * share).round(2)

    # Management fee payable: previous payable + this class's accruals since + late fees the approver chose
    # to include − its part of the payments since, late payments included (split by what each class owed,
    # E197–E200; R9.13, R9.17 — H106, E336, E337)
    mgmt_accrued = inputs.mgmt_fee_accrued_cents(unit_type, prev_date)
    mgmt_paid = @paid[:mgmt].fetch(unit_type, 0)
    late = EvergreenLateFees.call(fund, unit_type, nav_date, draft: nav)
    trim_late_decisions(nav, late.late_cents)
    nav.mgmt_fee_payable_cents = (prev&.mgmt_fee_payable_cents.to_d + mgmt_accrued + nav.late_included_cents - mgmt_paid).round(2)
    # What this NAV accounted for: its own period plus every late amount decided either way, so nothing
    # decided is ever late again (R9.15); and its share of payments, late ones included (H105, E336)
    nav.mgmt_fee_accounted_cents = (mgmt_accrued + nav.late_decided_cents).round(2)
    nav.mgmt_fee_paid_accounted_cents = mgmt_paid.to_d.round(2)
    nav.mgmt_fee_accrued_to = inputs.mgmt_fee_accrued_to(unit_type)

    # Performance fee payable: previous payable + the previous NAV's crystallised fee − payments since
    crystallised = prev&.crystallised ? prev.perf_fee_accrued_cents.to_d : 0
    nav.perf_fee_payable_cents = (prev&.perf_fee_payable_cents.to_d + crystallised - @paid[:perf].fetch(unit_type, 0)).round(2)

    # Class expenses payable: previous + this class's expenses since − its payments since; this class
    # only, and set before the performance fee so no fee is charged on money the class spent (H4, H5, E15)
    movements = @class_expenses[unit_type]
    nav.class_expenses_payable_cents = if term.class_expenses?
                                         (prev&.class_expenses_payable_cents.to_d + movements[:expensed] - movements[:paid]).round(2)
                                       else
                                         0 # E16: a class without its own entries has no such line
                                       end

    nav.units_outstanding = inputs.units_for(unit_type)
    apply_performance_fee(nav, term, inputs, unit_type)
    apply_overrides(nav, term)

    # The period's accruals and payments, as counted now, so the Fees tab can show how the payable was
    # reached (previous payable + accrued − paid) without re-reading a ledger that may have changed since
    nav.breakdown = breakdown(setting, inputs, prev, share, unit_type, term)
                    .merge("mgmt_fee_accrued_cents" => mgmt_accrued.round(2).to_s, "mgmt_fee_paid_cents" => mgmt_paid.to_d.round(2).to_s,
                           "late_mgmt_fee_included_cents" => nav.late_included_cents.round(2).to_s,
                           "late_mgmt_fee_excluded_cents" => nav.late_excluded_cents.round(2).to_s,
                           "late_mgmt_fee_paid_cents" => @late_paid.round(2).to_s)
    # The payable line's working names what the approver chose to include and any late payment (H106, E336)
    late_note = []
    late_note << "+ #{(nav.late_included_cents / 100).round(2).to_s('F')} late fee included" if nav.late_included_cents.positive?
    late_note << "incl. #{(@late_paid / 100).round(2).to_s('F')} late payments (fund-wide)" if @late_paid.positive?
    nav.breakdown["mgmt_fee_payable"] = "#{nav.breakdown['mgmt_fee_payable']} #{late_note.join('; ')}" if late_note.any?
    nav.inputs_fingerprint = NavStaleness.fingerprint(nav)
    nav.save!
    nav
  end

  # E341: late entries reversed after a decision — a decision can't cover more than is late, so the newest
  # ones go (the approver decides again on what is left) and the audit trail says why
  def trim_late_decisions(nav, late_cents)
    decisions = nav.late_fee_decisions_list.dup
    removed = false
    while decisions.any? && decisions.sum { |d| d["amount_cents"].to_d } > late_cents
      decisions.pop
      removed = true
    end
    return unless removed

    nav.late_fee_decisions = decisions.presence
    nav.audit_comment = "Late fee decision removed: the late amount changed"
  end

  # A class's own expenses and payments recorded since its previous NAV, by entry date (E17, E21);
  # nothing for a class that names no entries (E16)
  def class_expense_movements(inputs, unit_type)
    term = inputs.setting.terms_for(unit_type)
    return { expensed: 0.to_d, paid: 0.to_d } unless term.class_expenses?

    since = inputs.previous_nav(unit_type)&.nav_date
    { expensed: inputs.ledger_sum_cents(term.class_expense_entry_name, since, inputs.nav_date),
      paid: inputs.ledger_sum_cents(term.class_expense_paid_entry_name, since, inputs.nav_date) }
  end

  # Fee payments since the previous NAV, split by what each class owed before them — previous payable
  # plus this period's management accruals / the previous NAV's crystallised performance fee. Any
  # excess (over-payment), or a payment when nothing is owed, is split by value share (E197–E200).
  # => { mgmt: { unit_type => cents }, perf: { unit_type => cents } }
  def fee_payments_by_class(inputs, unit_types, shares)
    setting = inputs.setting
    prevs = unit_types.index_with { |ut| inputs.previous_nav(ut) }
    # One payment window for the fund: since its most recent previous NAV (classes are drafted together)
    since = prevs.values.compact.map(&:nav_date).max
    # Late fees already chosen for inclusion on this date's drafts are owed too (R9.13)
    drafts = FundNav.where(fund_id: inputs.fund.id, nav_date: inputs.nav_date, unit_type: unit_types).index_by(&:unit_type)
    mgmt_owed = unit_types.index_with do |ut|
      prevs[ut]&.mgmt_fee_payable_cents.to_d + inputs.mgmt_fee_accrued_cents(ut, prevs[ut]&.nav_date) + drafts[ut]&.late_included_cents.to_d
    end
    perf_owed = unit_types.index_with do |ut|
      p = prevs[ut]
      p&.perf_fee_payable_cents.to_d + (p&.crystallised ? p.perf_fee_accrued_cents.to_d : 0)
    end
    # R9.17 (E336, E337): late payments — dated in an approved period, never counted — always join this
    # date's payments, split the same way: the cash line already shows them gone
    @late_paid = EvergreenLateFees.late_paid_cents(inputs.fund, inputs.nav_date)
    mgmt_paid = inputs.ledger_sum_cents(setting.mgmt_fee_paid_entry_name, since, inputs.nav_date) + @late_paid
    { mgmt: split_payment(mgmt_paid, mgmt_owed, shares),
      perf: split_payment(inputs.ledger_sum_cents(setting.perf_fee_paid_entry_name, since, inputs.nav_date), perf_owed, shares) }
  end

  def split_payment(paid, owed, shares)
    owed = owed.transform_values { |v| [v, 0].max }
    total = owed.values.sum
    covered = [paid, total].min
    excess = paid - covered
    owed.keys.index_with do |ut|
      (total.positive? ? covered * owed[ut] / total : 0) + (excess * shares.fetch(ut, 0))
    end
  end

  # NAV per unit before the fee drives the accrual; the accrual then reduces NAV (H29)
  def apply_performance_fee(nav, term, inputs, unit_type)
    nav.perf_fee_accrued_cents = 0
    nav.recompute_totals!(initial_price_cents: term.initial_price_cents)
    hwm, hwm_date = inputs.high_water_mark(unit_type)
    nav.hwm_cents = hwm
    return unless term.performance_fee? && nav.units_outstanding.positive?

    days = hwm_date ? (nav.nav_date - hwm_date).to_i : 0
    result = PerformanceFeeCalculator.accrued(term:, nav_per_unit_before_cents: nav.nav_per_unit_before_perf_cents,
                                              hwm_cents: hwm, units: nav.units_outstanding, days:)
    nav.perf_fee_accrued_cents = result.fee_cents
    nav.recompute_totals!(initial_price_cents: term.initial_price_cents)
  end

  # Overrides survive a re-draft: the overridden value replaces the computed one (H4)
  def apply_overrides(nav, term)
    return if nav.overrides_hash.blank?

    nav.overrides_hash.each { |line, o| nav["#{line}_cents"] = o["value_cents"].to_d }
    nav.recompute_totals!(initial_price_cents: term.initial_price_cents)
  end

  def breakdown(setting, inputs, prev, share, unit_type, term)
    # The orders behind the dealing-in-progress line, so the GP can see what was set aside (E201)
    items = inputs.dealing_in_progress.key?(unit_type) ? inputs.dealing_in_progress[unit_type][:items] : []
    dealing = items.map { |label, cents| "#{label}: #{(cents / 100).round(2).to_s('F')}" }.join("; ")
    {
      "investments_fmv" => "Portfolio fair value on #{inputs.nav_date}",
      "cash" => "Ledger balance \"#{setting.cash_entry_name}\" (class share, plus this class's money for orders not yet dealt)",
      "dealing_in_progress" => dealing.presence || "No orders in progress",
      "other_assets" => "Ledger balance \"#{setting.other_assets_entry_name}\"",
      "other_liabilities" => "Ledger balance \"#{setting.other_liabilities_entry_name}\"",
      "mgmt_fee_payable" => "Previous payable + accruals − \"#{setting.mgmt_fee_paid_entry_name}\" (split by what each class owed)",
      "perf_fee_payable" => "Previous payable + crystallised − \"#{setting.perf_fee_paid_entry_name}\" (split by what each class owed)",
      "perf_fee_accrued" => "Class high-water mark",
      # H4: names the class's own entries; E16: none named
      "class_expenses_payable" => if term.class_expenses?
                                    "Previous payable + \"#{term.class_expense_entry_name}\" − \"#{term.class_expense_paid_entry_name}\" (this class only)"
                                  else
                                    "No class expense entries"
                                  end,
      "unclaimed_class_entries" => @unclaimed,
      "class_share" => share.to_s,
      "previous_nav_id" => prev&.id
    }
  end
end
