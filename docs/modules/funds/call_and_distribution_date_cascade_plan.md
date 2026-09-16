# Editable Call Date / Distribution Date with Cascade (Implementation Plan)

> Status: planned, not yet implemented. Saved for reuse when this is picked up.

## Context

Today, `CapitalCall#call_date` isn't even shown on the call's edit form (only on `new`), and
`CapitalDistribution#distribution_date` is shown but HTML-`disabled` once the record is
persisted — so in practice neither date can be corrected after creation. The goal is to make both
editable, with the edit cascading to the child records that were originally stamped with a copy
of that date at creation time:

- `CapitalCall#call_date` → `CapitalRemittance#remittance_date` (all `capital_remittances` for
  that call)
- `CapitalDistribution#distribution_date` → `CapitalDistributionPayment#payment_date` (all
  `capital_distribution_payments` for that distribution)

A plain silent cascade is risky: both child date fields feed exchange-rate lookups used to
compute money fields, so changing them can shift previously-computed amounts. A modal warning
must precede the change, explaining the consequences.

**Decisions locked in for this implementation:**
- **Overwrite**, not delta-shift: every child's date field is set to exactly the new parent date,
  even if a child had previously been edited independently (both `remittance_date` and
  `payment_date` have their own edit forms today).
- **Include finalized records**: verified remittances and completed distribution payments are
  cascaded too, not skipped.
- **Auto-trigger recompute**: after the cascade, automatically enqueue the existing "Recompute
  Fees" jobs (`CapitalRemittancesRecomputeFeesJob`, `CapitalDistributionPaymentRecomputeFeesJob`)
  so fee/exchange-rate-dependent amounts reflect the new date.
- **UI**: date field stays inline in the existing edit form (not a separate action/route); a
  confirm-gate modal intercepts submission when that field changed, explaining side effects,
  before the normal PATCH goes through.

**What the cascade does and does not change, precisely** (traced through
`CapitalRemittanceUpdate` / `CapitalDistributionPaymentUpdate`, the ops the recompute jobs already
call per-record):
- `CapitalRemittance`: only the `remittance_date` column is overwritten directly. The
  auto-triggered recompute re-runs `calc_call_amount_cents(recompute_call_amount: true)`, which
  re-derives `call_amount_cents`/`folio_call_amount_cents`/`computed_amount_cents` for
  "Percentage of Commitment" and "Investable Capital Percentage" call bases using the *new*
  `remittance_date` as the FX "as of" date (`capital_remittance_call_basis.rb:19,56`) — so these
  can shift. Fee currency conversions (`convert_fees`) only backfill fields that are still zero
  (`capital_remittance_fees.rb:10-31`), so already-populated fee conversions do not change.
  `set_status` still keys off `capital_call.due_date`/`verified`, untouched by this. `payment_date`
  on the remittance is untouched (it's derived from actual payments/`due_date`, not `call_date`).
- `CapitalDistributionPayment`: only `payment_date` is overwritten. The recompute
  (`setup_distribution_fees`) rebuckets account entries by each `DistributionFee`'s own configured
  date range, not by `payment_date`, so `income`/`cost_of_investment`/`tax`/`expense`/`net_payable`
  generally do not shift from this alone.
  **Known gap, to surface in the modal copy**: `tracking_*_cents` fields (tracking-currency
  amounts) are computed by a separate `TrackingCurrencyJob`, keyed off `payment_date` as the FX
  date, and are bucketed by distinct date. That job is not part of "Recompute Fees" and is not
  auto-triggered by this cascade — tracking amounts for affected payments can go stale until
  someone reruns that job. This is out of scope to fix here; the modal will say so plainly.

## Implementation

### 1. Two new background jobs (mirror `CapitalRemittancesRecomputeFeesJob`'s shape/notifications)

- `app/packs/funds/capital_calls/jobs/capital_call_date_change_job.rb` — new `< BulkActionJob`.
  Loads the `CapitalCall`, iterates `capital_call.capital_remittances.find_each` (bounded to one
  call's investors — safe per-record iteration, no `.pluck.uniq`/no loading extra columns), calls
  `capital_remittance.update!(remittance_date: capital_call.call_date)` per record inside
  `Chewy.strategy(:sidekiq)` (matches the existing recompute job so the search index stays in
  sync), with the same per-record rescue/error-email pattern as
  `CapitalRemittancesRecomputeFeesJob`. On completion, enqueues
  `CapitalRemittancesRecomputeFeesJob.perform_later(capital_call.id, user_id)`.
- `app/packs/funds/capital_distribution_payments/jobs/capital_distribution_date_change_job.rb` —
  same shape for `capital_distribution.capital_distribution_payments.find_each`, updating
  `payment_date`, then enqueuing `CapitalDistributionPaymentRecomputeFeesJob`.

Using `.update!` per record (not `update_all`) is deliberate: it runs model callbacks
(`update_index('capital_remittance')` Chewy indexing, `before_save :set_investor_name`,
`before_validation :ensure_commitment`) so the search index and derived fields don't go stale —
consistent with how the existing recompute jobs already do per-record `.find_each` + save rather
than bulk SQL.

### 2. Wire the cascade trigger into the existing update paths

- **CapitalCall** already updates through the Trailblazer op
  `app/packs/funds/capital_calls/services/capital_call_update.rb`. Add a step:
  ```ruby
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :generate_capital_remittances
  step :cascade_call_date_change   # new
  step :send_notification
  ```
  Implemented in `CapitalCallAction` (`app/packs/funds/capital_calls/services/capital_call_action.rb`):
  ```ruby
  def cascade_call_date_change(_ctx, capital_call:, current_user: nil, **)
    CapitalCallDateChangeJob.perform_later(capital_call.id, current_user.id) if capital_call.saved_change_to_call_date? && current_user
    true
  end
  ```
  `saved_change_to_call_date?` is read after `save`, so it only fires on an actual change.
  `CapitalCallsController#update` needs to pass `current_user:` into the op call
  (`CapitalCallUpdate.call(capital_call: @capital_call, current_user:)`).

- **CapitalDistribution** updates via plain `@capital_distribution.update(...)` directly in
  `CapitalDistributionsController#update` (no Trailblazer op exists for it — not introducing one
  for this small addition). After a successful update:
  ```ruby
  if @capital_distribution.update(capital_distribution_params)
    CapitalDistributionDateChangeJob.perform_later(@capital_distribution.id, current_user.id) if @capital_distribution.saved_change_to_distribution_date?
    ...
  ```

### 3. Views — make both dates editable, with a confirm-gate modal

- `app/packs/funds/capital_calls/views/capital_calls/_edit_form.html.erb`: add the missing
  `call_date` field (mirrors the `due_date` field already there, `_form.html.erb:77-78` for
  reference).
- `app/packs/funds/capital_distributions/views/capital_distributions/_form.html.erb:52-53`: drop
  `disabled:` from the `distribution_date` field specifically (leave the shared `disabled` local
  untouched for the other fields it still gates — `distribution_on`, sold investments,
  `reinvestment`).
- Both forms get a `data-controller="date-change-warning"` wrapper (new shared Stimulus
  controller, generic — not model-specific) around the form, with:
  - `data-date-change-warning-original-value="<%= capital_call.call_date.iso8601 %>"` on the
    wrapper, `data-date-change-warning-target="input"` on the date field itself, and
    `data-date-change-warning-target="modal"` pointing at the modal's DOM id.
  - Submit is intercepted only when the field's current value differs from the original; the
    modal is shown (`bootstrap.Modal`), and only its own "Confirm" button calls
    `form.requestSubmit()` to actually proceed. "Cancel" reverts the input to the original value
    and closes the modal.
- Modal partials (new files, each rendered as a **sibling of `FormCard`/the form**, not nested
  inside it — same reasoning as the modal-outside-collapsible convention used for
  `_reset_two_factor_modal.html.erb`): `_call_date_change_modal.html.erb` under
  `capital_calls/views/capital_calls/`, `_distribution_date_change_modal.html.erb` under
  `capital_distributions/views/capital_distributions/`. Both reuse the existing
  `action-summary__*` classes from `action_summary_modal.scss` (the "Immediate Actions" pattern
  already used by `_reset_two_factor_modal.html.erb`):
  - Intro callout: "The following will happen when you save this change."
  - Card (amber): "N remittances will be re-dated" (count computed at render time from
    `capital_call.capital_remittances.count`, plus how many are verified) — "including M already
    verified" for the call case, "including M already completed" for the distribution case, per
    the include-finalized-records decision.
  - Card (blue): "Fees will be recomputed automatically" — names the auto-triggered recompute job
    in plain language, and that FX-sensitive amounts (called amount / folio amount) may change as
    a result.
  - Card (grey): "Tracking-currency amounts are not automatically refreshed" (the known gap above)
    — distribution modal only.
  - Card (purple): "Already-generated documents/notices are not regenerated" — both.

### 4. Cucumber coverage (no RSpec)

Add scenarios to `features/fund/capital_calls.feature` and
`features/fund/capital_distributions.feature` (the closest existing analog is the "recompute
fees" scenario shape already in `capital_calls.feature:71-88`):
- Editing `call_date` on an existing call updates `remittance_date` on all its remittances
  (including a verified one) to the new date, and triggers the recompute-fees job (assert via the
  resulting recomputed amount, or via enqueued job in the `:inline` adapter per project
  convention).
- Same shape for `distribution_date` → `capital_distribution_payments.payment_date`, including a
  completed payment.
- A scenario asserting the warning step/copy appears (feature-level: that the count shown matches
  the number of remittances/payments).

## Verification

- `bin/rails runner` smoke check in a rails console is not the right tool here (mutates data) —
  rely on the new Cucumber scenarios above, run by the user (Claude does not run Cucumber itself).
- Manually confirm in the edit views: changing `due_date` alone (call) or any other field (both
  models) does **not** pop the modal — only a genuine change to `call_date` /
  `distribution_date` does.
- Confirm the Chewy index is still updated for touched remittances/payments (per-record
  `.update!` inside `Chewy.strategy(:sidekiq)`, matching the existing recompute jobs).
