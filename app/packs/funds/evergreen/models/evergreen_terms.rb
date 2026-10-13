# The effective terms for one unit class of an evergreen fund: the class's override where it has
# one, otherwise the fund value. Frozen, so callers can't mutate settings through it.
# Worked examples E4, E5 — openspec/changes/open-ended-funds/design.md#worked-examples
EvergreenTerms = Data.define(
  :unit_type, :notice_days, :lock_up_months, :lock_up_type, :early_redemption_fee,
  :min_initial_subscription_cents, :min_additional_subscription_cents, :min_holding_cents,
  :initial_price_cents, :perf_fee_model, :perf_fee_pct, :hurdle_pct, :hurdle_type, :crystallisation,
  :class_expense_entry_name, :class_expense_paid_entry_name
) do
  def hard_lock_up?
    lock_up_type == "hard"
  end

  def lock_up?
    lock_up_months.to_i.positive?
  end

  # Early-redemption fee % for units of a given age (months since allotment): a flat rate, or the
  # first schedule band whose [from, to) range contains the age. Units past the lock-up pay none.
  # Worked example E5 (3 % under 12 months, 2 % for 12–24 months)
  def early_fee_pct_for(age_months)
    fee = early_redemption_fee || {}
    schedule = fee["schedule"]
    if schedule.present?
      band = schedule.find { |b| age_months >= b["from"].to_i && age_months < b["to"].to_i }
      band ? band["pct"].to_d : 0.to_d
    else
      age_months < lock_up_months.to_i ? fee["pct"].to_d : 0.to_d
    end
  end

  # The class charges its own expenses through two named ledger entries (evergreen-share-classes H4, E16)
  def class_expenses?
    class_expense_entry_name.present? && class_expense_paid_entry_name.present?
  end

  def performance_fee?
    perf_fee_model == "class_hwm" && perf_fee_pct.to_d.positive?
  end
end
