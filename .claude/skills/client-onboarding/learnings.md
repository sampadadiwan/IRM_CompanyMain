# Learnings (append-only)

Add one entry per discovery: date, what happened, what to do differently, and where in the code
it was confirmed. Promote a learning into SKILL.md or importer-behaviour.md once it is a rule.

## 2026-10-18 — design session

- Extra import columns are not simply dropped: single-form imports auto-create TextField custom
  fields; commitments/KYCs create none. Create typed fields first. (form_type.rb:36)
- KYC forms carry 80–280 custom fields on real clients — budget most mapping effort there.
- Ops retry imports nearly row by row (Ambit: 64 KYC uploads for 74 rows). Pre-validation is the
  biggest win.
- Sandbox redirects notifications rather than dropping them — the ops inbox doubles as an email
  preview before go-live.

## 2026-10-18 — first real trial: Orios Venture Partners Fund I (dev, entity 1629, all writes via API)

Source: one MIS sheet (128 folios, ₹300 Cr, 515 drawdowns, 774 redemption + 1,022 gain lines) and 4 redacted SOAs.

- **Write real Excel date cells, never date text.** `ImportUtil#parse_date_cell` uses a Date cell as is but sends text
  through `Date.local_parse` (job locale): `05/04/2021` became 4 May. 41/128 commitment dates and 4/6 call due dates
  were swapped on the first upload. Fixed via CapitalCommitment "Update Only = Yes" and undo + re-import of calls.
- **Emit every template column, even optional ones** — `validate_headers` rejects the whole file ("Column(s) not found:
  Tags, Sector").
- **Commitments need a form type with a tag first** (`get_form_type`, import_util.rb:444): create it via
  `POST /form_types.json {"form_type":{"name":"CapitalCommitment","tag":"Default"}}` and put the tag in "Form Tag".
  A fresh entity has none, so every commitment row fails "Form Tag not specified".
- **Call import always needs an "Exchange Rates" sheet** (header only for single-currency funds).
- **Per-investor drawdown dates → sequence calls** (user decision): "Drawdown 1st…Nth", Call Basis "Upload",
  Generate Remittances "No", then CapitalRemittance rows with each folio's actual amount and date, then payments.
- **After payments: approve each call** (`POST /capital_calls/:id/approve.json`) **then bulk-verify**
  (`POST /capital_remittances/bulk_actions.json?bulk_action=Verify&capital_call_id=…&verified=false&collected_amount_positive=true`).
  Payment import does not verify remittances of unapproved calls.
- **Upload "status: Completed" does not mean success** — Fund and FundUnitSetting uploads said Completed with every
  row failed. Always check counts (G8) and the per-row errors.
- **Rollups can be wrong while rows are right**: after 515 payments the fund showed ₹300.25 Cr collected and folio 055's
  commitment ₹1.5 Cr vs ₹2 Cr in its remittances. Reconcile against the rows, and report rollup drift.
- **Entities cannot be deleted** (root folder FK cycle; `EntityPolicy#destroy?` false). Use a fresh entity per trial.
- **Investors are soft-deleted** (paranoia); placeholder investor entities (by email) persist across retries.
- Placeholders used: names/PAN/emails redacted → "Orios Investor <folio>", `orios.<folio>@example.com`.
- Assumptions recorded for Orios: commitment date = first drawdown; fees/carry 0%; "Various" drawdowns = one payment
  on first close 2013-12-20 (folios 001D, 003).
- **Distributions** (user decision: like drawdowns): redemptions → "Redemption 1st…6th" (gross as Face Value For
  Redemption), gains → one distribution per MIS gain type/FY (gross as Income), Generate Payments "No", then payments
  with TDS / Net Amount (NumberField) and Payment Type as custom fields created first via
  `POST /form_types.json` with `form_custom_fields_attributes` (the template has no TDS column).
- **One payment per folio per distribution** ("Folio has already been taken"). Orios' NRE folios had two 5th
  redemption lines; their SOA labels them "(5th) - LTCG" and "(5th) - STCG" → a separate "Redemption 5th - STCG"
  distribution. Then correct the original header (`PATCH /capital_distributions/:id.json cost_of_investment`) so it
  equals its payments. Read the client's statements to resolve such modelling questions.
- **Approve distributions** (`POST /capital_distributions/:id/approve.json`); it returns 500 (P11) but approves —
  verify in data, not by status code.
- Orios result: 1,795 distribution payments; income ₹96.9276 Cr, face value ₹287.0682 Cr, TDS ₹32.5559 Cr,
  net ₹351.4399 Cr — all equal to the MIS. Fund distributed ₹383.9958 Cr = income + face value.
- Orios inconsistency to raise: folio 055 SOA dates the 5th STCG redemption 01/Feb/24 on page 1 and 28/Jun/24 on
  page 2; the MIS says 2024-02-01 (used).
- **Wait for the payment-import fix job before bulk-verifying** (P6, root cause confirmed): the payment import queues
  `ImportCapitalRemittancePaymentsFixCountsJob` (~60 s for 515 rows) which recounts fund/commitment totals; bulk
  verify running at the same time loses or double-counts increments (Orios: fund +₹25 L, folio 055 −₹50 L). Until the
  app serialises them, poll until the upload's follow-up alert "Recalculating counters completed" before the next write.
- **Units are a separate step — imports create none.** For a unit-based fund: give each call `Unit Price/Premium`
  (e.g. `A:100:0,…`) at import, then `PATCH /capital_calls/:id/allocate_units` (FundUnitsJob, queue `low`); set
  `unit_prices` on each redemption distribution (`PATCH /capital_distributions/:id.json
  {"capital_distribution":{"unit_prices":{"A":"100",…}}}`, answers 500 per P11 but saves), then
  `PATCH /capital_distributions/:id/redeem_units`. Gain distributions (no face value) redeem nothing, correctly.
  Reconcile each folio's units against the client's balance units — Orios: 3,00,00,000 issued, 2,87,06,821.1423
  redeemed, 12,93,178.8577 balance; all 128 folios equal the MIS "Balance Units" column.

## 2026-10-18 — production-style re-run (entity 1630, fund 376, funds-json-api-hardening build)

- **Done with the API only, writes and checks** (hard rule 1a): every figure matched the MIS. Checks:
  `scripts/api_check.rb commitments|drawdowns|distributions|units` (lists with `?all=true`, `/funds/:id/summary.json`,
  `units_quantity` on remittances and distribution payments, `custom_fields` for TDS/net).
- The Fund import works on this build (P3); `outcome` reports warning-only uploads as "succeeded".
- Bulk verify straight after the payment import no longer drifts totals (P6) — the end-of-verify recount converges.
- The app refuses bulk verify on an unapproved call ("Verified cannot be set while the call is not approved") — approve first.
- Don't put "From Currency / To Currency / Exchange Rate / As Of" in a single-currency distribution file: they become
  junk TextField custom fields (P13).
- Large uploads (1,795 rows) take > 5 min — poll longer; `outcome` stays "running" until done.
- Shell gotcha: zsh does not word-split `$ids` — loop over an explicit list.
- Remaining API gaps: P12 (no bulk approve/allocate/redeem), G16 (fund dates not in JSON), G17 (no `approved` in
  call/distribution JSON), G18 (allocate/redeem answer 302; no completion signal).

## 2026-10-18 — staging run (dev.altconnects.com, entity 1548, fund 361), resumed across sessions

- **Resuming:** the earlier session's journal stopped at "sandbox on", but the API showed uploads 2823–2826 (fund, unit
  settings, investors, commitments) already succeeded. Always read the uploads list before re-importing anything.
- On this build `approve` (calls and distributions) answers **201**, `unit_prices` PATCH answers **200**, and
  `allocate_units` / `redeem_units` answer **202 `{"status":"queued"}`**, so P11 and G18's reply look fixed. There is still no
  completion signal: poll `units_quantity` on remittances / distribution payments until it stops changing (about 30 s for 515, about 90 s for 1,795).
- Distribution payment form fields: `POST /form_types.json` with `form_custom_fields_attributes` works, but the form-type
  JSON does not list its fields. Confirm them through the payment upload's empty `custom_fields_created`.
- **Tick-and-tie reconciliation** (`scripts/recon_report.rb`): walk the raw client rows independently of the transform and
  match each one to an app record by folio + date + amount, taking each match out of a pool. Then report the leftovers (app rows with no
  client row), the client's own total rows, a 128 × 13 per-folio table, and per call / per distribution header = Σ rows. On Orios:
  10,008 row checks, 15 totals, 1,664 folio figures, all tie.
- **Investor access:** write only `ImportInvestorAccess::STANDARD_HEADERS`. The sample `investor_access.xlsx` has an extra
  "Send Confirmation Email" column that is not standard and would become a custom field. Each access creates a real
  user, even for placeholder emails, so placeholders must be swapped for real contacts before go-live. The access JSON has no
  `email_enabled` (gap).
