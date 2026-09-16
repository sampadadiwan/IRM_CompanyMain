# TrackingCurrencyJob — High-Severity Bug Fixes

**Date:** 2026-04-28  
**File:** `app/packs/funds/funds/jobs/tracking_currency_job.rb`

---

## Fix 1 — Scope leak: `force: false` protection was bypassed

### The bug

Four methods built a filtered `scope` to select only unprocessed records (`tracking_amount_cents == 0`), but then ran `update_all` against the **unfiltered** fund association. The filter controlled which **dates** were selected for processing, but the actual SQL update hit **every record on those dates**, including ones already correctly converted.

Affected methods:
- `convert_remittance_payments`
- `convert_remittances`
- `convert_distributions`
- `convert_commitment_adjustments`

### Concrete scenario

Fund has remittance payments on `2024-01-15`:

| Payment | `tracking_amount_cents` | Expected with `force: false` |
|---------|------------------------|------------------------------|
| A | 1,500,000 (already set) | Leave untouched |
| B | 0 (new) | Convert with today's rate |

**What happened:** B's date (`2024-01-15`) appeared in `scope.pluck`, so the update ran `fund.capital_remittance_payments.where(payment_date: '2024-01-15').update_all(...)` — overwriting both A and B with today's rate. A's historically correct tracking amount was silently corrupted. A date where all records were already processed was safe; the bug only fires when even one record on a date is unprocessed.

### Before

```ruby
# convert_remittance_payments
scope.pluck(:payment_date).compact.uniq.each do |date|
  rate = fund.tracking_exchange_rate(exchange_rate_date: date).rate
  fund.capital_remittance_payments.where(payment_date: date)   # ← unfiltered relation
      .update_all("tracking_amount_cents = amount_cents * #{rate}")
end

# convert_remittances
scope.pluck(:remittance_date).compact.uniq.each do |date|
  rate = fund.tracking_exchange_rate(exchange_rate_date: date).rate
  fund.capital_remittances.where(remittance_date: date).find_each do |cr|  # ← unfiltered
    cr.update_columns(...)
  end
end

# convert_distributions
scope.pluck(:payment_date).compact.uniq.each do |date|
  rate = fund.tracking_exchange_rate(exchange_rate_date: date).rate
  fund.capital_distribution_payments.where(payment_date: date).update_all(  # ← unfiltered
    "tracking_net_payable_cents = net_payable_cents * #{rate}, ..."
  )
end

# convert_commitment_adjustments
scope.pluck(:as_of).compact.uniq.each do |date|
  rate = fund.tracking_exchange_rate(exchange_rate_date: date).rate
  fund.commitment_adjustments.where(as_of: date)   # ← unfiltered
      .update_all("tracking_amount_cents = amount_cents * #{rate}")
end
```

### After

```ruby
# All four methods — update now targets `scope` instead of the fund association
scope.pluck(:payment_date).compact.uniq.each do |date|
  rate = fund.tracking_exchange_rate(exchange_rate_date: date).rate
  scope.where(payment_date: date)   # ← respects the force: false filter
       .update_all("tracking_amount_cents = amount_cents * #{rate}")
end
```

The fix is identical in all four methods: replace `fund.<association>.where(date_field: date)` with `scope.where(date_field: date)`.

---

## Fix 2 — Capital commitments: wrong formula for `tracking_committed_amount_cents`

### The bug

The original code converted `committed_amount_cents × rate_at(commitment_date)`, where `committed_amount_cents` is the **sum** of the original pledge plus all subsequent adjustments. Each adjustment happened at a different date with a different exchange rate. Multiplying the running total by a single point-in-time rate produces an incorrect figure.

Additionally, `tracking_adjustment_amount_cents` on `CapitalCommitment` (a `counter_culture` rollup of `CommitmentAdjustment#tracking_amount_cents`) was never rebuilt after `convert_commitment_adjustments` ran — because `update_all` bypasses ActiveRecord callbacks.

### Data model

```
capital_commitments
  tracking_orig_committed_amount_cents   ← orig pledge converted at commitment_date rate
  tracking_adjustment_amount_cents       ← counter_culture sum of adjustments' tracking amounts
  tracking_committed_amount_cents        ← total = orig + adjustments
```

`CapitalCommitmentShared#committed_amount_cents_before` and XIRR calculations read `orig_tracking_committed_amount_cents + adjustments.sum(:tracking_amount_cents)` — these were always correct from the adjustment-level data, but the displayed `tracking_committed_amount_cents` column was wrong.

### Concrete scenario

Fund currency: INR → Tracking currency: USD

| Event | Date | INR | Rate | Correct USD |
|-------|------|-----|------|-------------|
| Original commitment | 2024-01-01 | 10,000,000 | 0.01200 (83 INR/USD) | 120,000 |
| Top-up adjustment | 2024-06-01 | 1,000,000 | 0.01100 (91 INR/USD) | 11,000 |
| **Correct total** | | 11,000,000 | — | **131,000** |

**Old result** (commitment_date rate applied to the full total):
```
tracking_committed_amount_cents = 11,000,000 × 0.01200 = 132,000 USD  ← wrong by 1,000 USD
```

### Before

```ruby
def convert_capital_commitments(fund, user_id, force: false)
  scope = fund.capital_commitments
  scope = scope.where(tracking_committed_amount_cents: 0) unless force

  scope.pluck(:commitment_date).compact.uniq.each do |date|
    rate = fund.tracking_exchange_rate(exchange_rate_date: date).rate
    fund.capital_commitments.where(commitment_date: date).update_all(
      # This is incorrect - TODO fix
      "tracking_committed_amount_cents = committed_amount_cents * #{rate},
       tracking_orig_committed_amount_cents = orig_committed_amount_cents * #{rate}"
    )
  rescue StandardError
    @missing_rates << "Capital Commitments: #{fund.currency}->#{fund.tracking_currency} on #{date}"
  end
  {}
end
```

Problems:
1. `tracking_committed_amount_cents = committed_amount_cents * rate` — blends orig + adjustments under one rate.
2. Scope leak (same as Fix 1) — used `fund.capital_commitments` in the update, not `scope`.
3. `tracking_adjustment_amount_cents` counter-cache never rebuilt after adjustments were converted.
4. Guard was on `tracking_committed_amount_cents: 0` — once `committed_amount_cents` was non-zero, records were considered "done" even if orig/adjustment breakdowns were wrong.

### After

```ruby
def convert_capital_commitments(fund, user_id, force: false)
  scope = fund.capital_commitments
  # Guard on the orig field — it is the only one converted at a point-in-time rate.
  # tracking_committed_amount_cents is always recomputed at the end of this method.
  scope = scope.where(tracking_orig_committed_amount_cents: 0) unless force

  # Each commitment's original pledge is converted at its own commitment_date rate.
  # Adjustments are handled separately in convert_commitment_adjustments (each at their as_of rate).
  scope.pluck(:commitment_date).compact.uniq.each do |date|
    rate = fund.tracking_exchange_rate(exchange_rate_date: date).rate
    scope.where(commitment_date: date).update_all(
      "tracking_orig_committed_amount_cents = orig_committed_amount_cents * #{rate}"
    )
  rescue StandardError
    @missing_rates << "Capital Commitments: #{fund.currency}->#{fund.tracking_currency} on #{date}"
  end

  # Rebuild tracking_adjustment_amount_cents from commitment_adjustments.tracking_amount_cents.
  # update_all in convert_commitment_adjustments bypasses counter_culture callbacks, so we fix counts here.
  CommitmentAdjustment.counter_culture_fix_counts(where: { fund_id: fund.id })

  # tracking_committed_amount_cents is derived from its two tracking components.
  # Recompute for all commitments so the total stays consistent with orig + adjustments.
  fund.capital_commitments.update_all(
    "tracking_committed_amount_cents = tracking_orig_committed_amount_cents + tracking_adjustment_amount_cents"
  )

  {}
end
```

Changes:
1. Only converts `tracking_orig_committed_amount_cents` at commitment_date rate — the component that is genuinely point-in-time.
2. Scope leak fixed — `scope.where(commitment_date: date)` used in the update.
3. Calls `CommitmentAdjustment.counter_culture_fix_counts` to rebuild `tracking_adjustment_amount_cents` from the already-converted adjustment rows.
4. Final `update_all` derives `tracking_committed_amount_cents` from its two correct tracking components.
5. Guard moved to `tracking_orig_committed_amount_cents: 0` — the actual converted field.

---

## Summary of all changes

| Method | Change |
|--------|--------|
| `convert_remittance_payments` | Update targets `scope` not `fund.capital_remittance_payments` |
| `convert_remittances` | Update targets `scope` not `fund.capital_remittances` |
| `convert_distributions` | Update targets `scope` not `fund.capital_distribution_payments` |
| `convert_commitment_adjustments` | Update targets `scope` not `fund.commitment_adjustments` |
| `convert_capital_commitments` | Formula corrected: orig at commitment_date rate + counter_culture fix + derived total; scope leak fixed; guard field corrected |
