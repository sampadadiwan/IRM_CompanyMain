# Uploading Remittances on a Computed Capital Call (Design Note)

> Status: brainstorm / proposed, not yet implemented. Written 2026-09-20 after verifying the
> current code paths. Saved so the analysis can be reused when this is picked up.

## Context

A capital call is "computed" when its `call_basis` is anything other than `"Upload"` — today
`"Percentage of Commitment"`, `"Investable Capital Percentage"`, or an entity-specific basis
from `EntitySetting#call_basis`. There is no `computed` column; `CapitalCall::CALL_BASIS` is a
plain frozen array and `call_basis` is a string.

For a computed call the per-folio remittances are generated, not uploaded:

- `CapitalCall#setup_defaults` (`before_save`) forces `generate_remittances = true` whenever the
  basis is not Upload. The `generate_remittances = false` state is reachable only through the
  capital call importer, never the UI.
- `CapitalCall#generate_capital_remittances` enqueues `CapitalCallJob(id, "Generate")` when the
  percentage, amount to be called, or fund closes change. It runs on the `serial` queue.
- `CapitalCallJob` creates one `CapitalRemittance` per commitment in `capital_call.applicable_to`,
  with `created_by: "Call"`, skipping any folio that already has a remittance for the call. It is
  documented as idempotent and re-runnable.
- `CapitalCommitmentRemittanceJob` generates a remittance for a commitment that joins after the
  call was created, and skips calls whose basis is Upload.
- The amount math lives in `CapitalRemittanceCallBasis` and is dispatched from
  `CapitalRemittance#calc_call_amount_cents` on the **remittance's own** `call_basis`, which is
  inherited from the call unless the row was pre-stamped by the importer.

The question raised: can users upload remittances on a computed call, and what happens if we let
them?

## What the code does today

### The block is cosmetic

The only thing preventing an upload on a computed call is a CSS class in
`app/packs/funds/capital_remittances/views/capital_remittances/_index.html.erb`:

```erb
<!-- Disable upload if call basis is not Upload or if some remittances have been deleted (so people can upload them) -->
<% disabled = capital_call.call_basis != "Upload" && capital_call.capital_remittances.count == capital_call.fund.capital_commitments.count ? "disabled" : nil %>
```

applied as `class: "dropdown-item #{disabled}"` on the **Upload Remittances** menu item.

There is no corresponding guard in `CapitalRemittancePolicy`, `CapitalCallPolicy`,
`ImportUploadsController`, `ImportUpload`, or `ImportCapitalRemittance`. A direct request to
`new_import_upload_path` with `owner_type=CapitalCall` and `import_type=CapitalRemittance` is
accepted for a computed call.

### The guard already intends partial uploads

The comment and the count comparison show the intended rule: on a computed call, uploads are
allowed only to fill in folios whose remittances are missing (for example, deleted by mistake).
Two problems with the current implementation:

1. It compares against `fund.capital_commitments.count`, not `capital_call.applicable_to.count`.
   A call scoped to specific fund closes therefore never reaches "complete" and the button is
   always enabled.
2. Because the rule is only in the view, nothing stops a row for an existing folio; it just fails
   the `validates_uniqueness_of :folio_id, scope: :capital_call_id` validation with a generic
   message.

### The importer ignores the call's basis

`ImportCapitalRemittance` builds every row with:

```ruby
created_by: "Upload",
call_basis: "Upload"
```

regardless of the parent call's basis, and then calls `CapitalRemittanceCreate`. It only creates;
there is no update path. A row uploaded against a computed call therefore becomes an Upload-basis
row inside a computed call, which changes how that row behaves under **Recompute Fees** and
under the FX direction in `CapitalRemittanceFees#convert_fees`.

### Downstream processes that would interact with uploaded rows

| Process | Behaviour today |
|---|---|
| `CapitalRemittancesRecomputeFeesJob` | Runs `CapitalRemittanceUpdate(recompute_call_amount: true)` on every remittance of the call. Percentage/account-entry bases recompute the amount from the formula. Upload basis back-derives percentage from the amount, so the amount survives. |
| `CapitalCallDateChangeJob` | Re-dates every remittance to the new call date, then chains the recompute job above. |
| `CapitalCallJob` regeneration | Skips folios that already exist. Existing rows are **not** refreshed when the call percentage changes. |
| `CapitalCommitmentRemittanceJob` | Generates for late-joining folios on computed calls; skips Upload calls. |
| Counter culture (`CapitalRemittanceCounters`) | `call_amount_cents`, `capital_fee_cents`, `other_fee_cents` roll up to call, fund, commitment and investor KYC on commit. `collected_amount_cents` rolls up only when `verified` is true. |
| `verified_requires_approval` | Blocks setting `verified` on a persisted row without approval. Calls with `generate_remittances_verified` are born verified and Paid and may have a back-filled `CapitalRemittancePayment`. |
| `CapitalCallApprove` | Re-runs generation but blocks on unapproved notices. Nothing blocks amount changes after notices are sent. |

The user guide (`docs/user_guides/capital_calls_user_guide.md`) already documents the intended
rule: "Upload Remittances is disabled unless the call basis is 'Upload' or some remittances are
missing."

## What "enable upload on a computed call" could mean

These are three different features and should not be conflated:

1. **Fill gaps only.** Upload creates remittances for folios the generator did not produce. This
   is the current de-facto behaviour with a broken guard. Lowest risk.
2. **Override amounts.** Upload updates existing generated remittances with LP-specific amounts
   (side letter caps, a defaulting investor, a negotiated waiver). This is the realistic business
   ask and needs an update path the importer does not have.
3. **Replace generation.** Upload replaces the whole computed set. This is really "change the
   call's basis to Upload", which the edit form forbids after creation.

The recommendation below covers 1 and 2. Option 3 is out of scope; if wanted, model it as a
basis change with its own confirmation, not as an upload.

## Recommendation

Two stages. Stage 1 closes the gap that exists today with no schema change. Stage 2 adds the real
feature. Shipping Stage 1 first means Stage 2 cannot be reached by accident through the existing
upload path.

### Stage 1: make the current rule real

**1a. Enforce in the importer.** In `ImportCapitalRemittance`, when the parent call's basis is
not Upload, raise a readable error if a remittance already exists for that folio and call.

> Example: Fund Alpha, call CC-3 is Percentage of Commitment with 40 folios generated. A user
> uploads a sheet containing folio F-012, which already exists. Today the error is a uniqueness
> validation message. After the fix it reads: "F-012 already has a generated remittance on CC-3.
> Computed calls only accept uploads for missing folios."

**1b. Fix the button guard.** Compare against `capital_call.applicable_to.count`, not
`capital_call.fund.capital_commitments.count`. Use `exists?`/`count` on the relation, not a
Ruby-side load.

> Example: call CC-4 applies only to Close 2, which has 15 folios. The job generates 15 rows. The
> fund has 60 commitments total, so today the guard sees 15 vs 60 and leaves Upload enabled. With
> the fix it sees 15 vs 15 and disables it.

**1c. Do not stamp gap-fill rows as Upload basis on a computed call.** Let the row inherit the
call's basis (i.e. leave `call_basis` nil so `calc_call_amount_cents` sets it from the call) so
it behaves like its siblings under recompute and date changes. Keep `created_by: "Upload"` and
`import_upload_id` for audit. Rows uploaded to a genuine Upload-basis call keep today's
behaviour.

> Example: F-051 was created after the call and its remittance was deleted by mistake. The user
> uploads F-051 with the amount from the notice. Later Finance runs Recompute Fees. Because the
> row carries Percentage of Commitment basis, it recomputes to the same formula as the others
> rather than back-deriving a percentage from the uploaded number.

Stage 1 touches: `import_capital_remittance.rb`, `_index.html.erb`, and a Cucumber scenario in
`features/fund/fund_import.feature` covering (a) gap-fill accepted, (b) existing folio rejected
with the new message, (c) guard on a close-scoped call.

### Stage 2: explicit override mode

**2a. Separate entry point.** Add an **Override Remittances** action, or an "Override Existing"
Yes/No column in the sheet, so a user cannot overwrite forty rows by uploading the wrong file.
The default upload stays create-only.

> Example: the sample sheet gains a column "Override Existing". Rows marked No that match an
> existing folio fail with the Stage 1 error. Rows marked Yes update the existing row.

**2b. Update, do not create.** For override rows, load the existing remittance for that folio and
call, set the new amounts and fees, and run `CapitalRemittanceUpdate`. Counter culture handles
call, fund, commitment and KYC totals on commit. Keep `defer_counter_culture_updates` and the
counters fix-up job pattern the importer already uses.

> Example: F-020 was generated at 100,000. A side letter caps it at 80,000. The override sets
> `call_amount_cents` to 80,000 and the call's `call_amount_cents` drops by 20,000
> automatically.

**2c. Add a `manual_override` boolean on `capital_remittances`.** Set it on override. This is
preferable to flipping the row's `call_basis` to Upload, because a basis flip also changes FX
direction in `convert_fees` and hides the fact that the call is computed.

> Example: a JPY folio in a USD fund. If the row's basis were flipped to Upload, `convert_fees`
> would treat the uploaded number as folio currency and convert to fund currency. With the flag,
> the row keeps its computed basis and FX path. Only the amount is pinned.

**2d. Teach recompute and the date cascade to skip flagged rows.** In `calc_call_amount_cents`,
return early when `manual_override` is set, even if `recompute_call_amount` is true.
`CapitalRemittancesRecomputeFeesJob` and `CapitalCallDateChangeJob` then leave overridden rows
alone without needing their own checks. `setup_call_fees` should also be skipped for overridden
rows, since the uploaded fees are the intended ones.

> Example: after the F-020 override, the fund admin changes the call date, which chains a fee
> recompute. F-020 stays at 80,000. The other 39 rows recompute normally.

**2e. Preserve the original computed amount.** Keep `computed_amount_cents` as the formula result
and store the override reason (a text column or a key in `json_fields`).

> Example: the remittance grid shows F-020 as "Called 80,000 · formula 100,000 · override: side
> letter cap". The reconciliation agent can explain the 20,000 difference without guessing.

**2f. Refuse overrides on rows that are already downstream.** Reject an override if the row is
`verified`, has any `CapitalRemittancePayment`, or its call notice has been sent. Report those
rows in the import errors and still apply the rest of the sheet.

> Example: F-007 already paid 100,000 and is verified. The override sheet tries to set 90,000.
> The import reports "F-007 is verified with a recorded payment of 100,000. Reverse the payment
> before overriding." The remaining rows apply.

**2g. Leave the call's basis alone.** The call stays Percentage of Commitment. Late-joining
folios still auto-generate through `CapitalCommitmentRemittanceJob`. Edits to the call
percentage still trigger generation for missing folios.

> Example: a new commitment F-061 closes after the overrides. The job generates its remittance
> from the formula as usual. Nothing about the overrides affects it.

**2h. Surface overrides in the UI and notices.** Add an "Overridden" badge and grid filter on the
remittances tab, and a count in the call summary so a reviewer sees "40 remittances, 2
overridden" before approving. Consider including the flag in the call-notice template context so
a notice can show the negotiated amount explicitly.

> Example: the approver opens CC-3, sees the two overridden rows highlighted, checks the reasons,
> and only then approves and sends notices.

Stage 2 touches: a migration (`manual_override`, `override_reason`), `capital_remittance.rb`
(`calc_call_amount_cents` early return), `capital_remittance_fees.rb` (`setup_call_fees` skip),
`import_capital_remittance.rb` (override branch), the sample upload file, the remittances grid
and call summary partials, `FundAssistantDataManager`/MCP ontology if the flag should be
queryable, and Cucumber scenarios for override accepted, override refused on verified/paid/sent
rows, and override surviving recompute and date cascade.

## Risks and open questions

- **Uniqueness is validation-only.** `folio_id` per call has no unique DB index
  (`schema.rb` `capital_remittances` indexes). The create-only importer gave accidental protection
  against duplicates; an update path removes that. Consider adding the unique index as part of
  Stage 2.
- **Existing regeneration quirk.** `CapitalCallJob` skips existing folios, so a percentage change
  on the call does not refresh already-generated rows. This is pre-existing, but users will
  notice it more once they can see "formula vs called" side by side. Decide whether regeneration
  should refresh non-overridden rows.
- **Notices already sent.** Nothing today blocks an amount change after notices go out. Stage 2f
  refuses the override; a revised-notice flow is a separate feature.
- **Reconciliation agent and AI data manager** read `call_basis` per call. With overrides, a
  call's basis no longer describes every row; both consumers should read `manual_override` when
  explaining a variance.
- **Option 3 (replace generation)** is deliberately excluded. If needed, implement as an
  explicit basis change with confirmation, not as an upload.

## Related

- `docs/modules/funds/call_and_distribution_date_cascade_plan.md` — the date cascade that chains
  the fee recompute this note has to protect overridden rows from.
- `docs/user_guides/capital_calls_user_guide.md` — documents the intended upload rule; update
  the FAQ when Stage 1 ships.
- `features/fund/fund_import.feature` — existing "Import capital remittance" scenarios on an
  Upload-basis call.
