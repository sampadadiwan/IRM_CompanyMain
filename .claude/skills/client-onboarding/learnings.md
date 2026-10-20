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

## 2026-10-19 — Inflexor (dev, entity 1631, fund 377): fund + portfolio side, API only

Source: one drawdown sheet (57 folios, one drawdown each, up to 3 payments per folio) plus portfolio company / investment / valuation
files already in template shape. Result: 1,088 / 1,088 recon checks via the API.

- **A header with symbols keys differently from a hand-made field.** For single-form imports (Investor, Valuation, PortfolioInvestment,
  CapitalRemittance) the json key is `FormCustomField.to_name(header)`, and "Initial Ownership (%)" becomes `initial_ownership_`
  (trailing underscore). A pre-created `initial_ownership` did not match, so the import auto-created a TextField. Name pre-created
  fields with `to_name(header)` exactly, or rename the header to plain words. Fixed afterwards with `PATCH /form_custom_fields/:id.json`
  (field_type + label) and `DELETE` of the empty duplicate.
- **Client files carry invisible characters:** names with embedded newlines and a leading BOM (U+FEFF). Clean them before matching.
- **One drawdown per folio, staggered notice dates:** one call (Upload basis); each folio's notice and due date go in remittance
  custom fields, because a remittance's standard due date is the call's.
- **Bulk verify's `count` is the number of payments, not remittances** (68 vs 54 verified). Check `verified` on the remittances.
- **Portfolio investments create their own valuations** (one per buy, at the price paid), so `/valuations.json` returns more rows
  than were imported. Filter by date when reconciling.
- **The valuation file may cover one instrument only.** To get FMV for the whole holding, add a valuation row per instrument held.
  Check: Σ net_quantity and Σ fmv per company equal the client's "no. of shares" and "stake valuation".
- When ops says "make reasonable assumptions and start", write each assumption against a client question id
  (`client_questions.md`) so the report's 1.7 table and the client's answers line up.

## 2026-10-19 — Inflexor KPI phase: portfolio KPIs from MIS workbooks, all through KpiWorkbookReader via the API

Ops decision: **every KPI value goes through the app's MIS reader** (`KpiWorkbookReader`), never a scripted `Kpi` import.
Result: 142 mappings; 4 of the 5 client files loaded as 3 workbooks (Butterfly's P&L + cash flow merged into one); 908 approved
KPIs, every value tied to its source cell. Scripts named below live in the client workspace (`~/work/onboarding/inflexor/scripts/`),
not in this repo: `kpi_labels.rb`, `build_kpi_mappings.rb`, `kpi_dry_run.rb`, `check_dryrun_cells.rb`, `merge_mis.rb`,
`kpi_upload.rb`, `kpi_recon.rb`.

- **Check labels before building mappings.** The client's KPI Info "Name in MIS" is often not the row label: "TOTAL" for several
  totals, notes in brackets, several lines in one cell. Match them the way the reader does (lowercase, no whitespace, exact) against
  the real row labels (`kpi_labels.rb`), and keep labels that contain commas or "and" whole.
- **One mapping per MIS label per company.** The reader treats a label with two mappings as ambiguous and skips it. Make the second
  KPI a `compute` copy of the first (e.g. Burn = Operating Cash Flow).
- **Composite KPIs = component mappings + a `compute` parent summing them.** Give components plain standard names (letters, digits,
  spaces): the formula substitution uses `\b`, which never matches a name ending in ")". Don't use "Parent Standard Kpi Name" — it
  renames children to "Parent - Child". Computed KPIs appear only after the components are approved.
- **Scope mappings to a sheet (`source_sheet`) when a label means different things in different sheets or files** (P&L "Rent" vs
  cash-flow "Rent", a therapy-only sheet repeating P&L lines, an "AOP vs Actual" sheet with untagged columns).
- **Always dry run (`POST /kpi_reports/validate_upload.json`), then check each `ok` cell against the source workbook** — the
  verdict can say ok and still be wrong (quarter read as a month, first segment column instead of Total, a year range read as June).
  All three were reader bugs, fixed the same day; only a cell-by-cell check caught them.
- **Approve only after tying stored KPIs to the source** (value at the cell named in the notes, period/date, one-to-one with the dry
  run). The KPI grid hides unapproved values unless `view_unapproved=true` — N/A there is not "nothing stored".
- **One KPI report per company + period + tag, one workbook per report.** When a client sends several files for a month (Butterfly:
  P&L + cash flow), merge them into one workbook, one sheet per statement ("P&L", "Cash Flow"), copied cell for cell
  (`scripts/merge_mis.rb`), point clashing mappings' Source Sheet at the new sheet names, dry-run, and upload to the month's report.
  Never park a file on another period's report — that workaround (Year report 2849) had to be deleted and redone.
- **After a migration, restart Puma and Sidekiq.** A new column (`source_sheet`) answered 200 to PATCH with the value echoed but read
  back null until both were restarted.
- API gotchas hit (all logged in api-gaps.md, most fixed same day): `/kpis.json` ignored `portfolio_company_id` (use
  `q[portfolio_company_id_eq]`), the reports list dropped older reports, KPI notes named the label column on sheets starting at B,
  a refresh never rewrites notes of approved unchanged values.

## 2026-10-19 — Rehearsal: Orios onto a fresh entity with only the skill's tools

Entity 1692 / fund 378, dev, check-data mode. Read → build → import → approve/verify → distributions → `apply_units --execute`
→ `fund_recon` → `gate`: **10,992 / 10,992 ✅** in about 14 minutes (almost all of it the app's import and unit jobs; payments
166 s, distribution payments ~170 s, units 300 s). First real run of `apply_units.rb --execute`: 6 allocations, 7 price +
redeem pairs, balance 12,93,178.8577 = the MIS.

- **Holes between tools** (no tool bugs): posting the fund and form types, approving + bulk-verifying calls, and approving
  distributions were hand-typed loops. Next: one `onboard.rb` that knows the order and runs/prints the next step.
- The payment upload says "some remittances were not marked Verified … calls are not approved" — expected: approve each call,
  then bulk Verify (the verify count is now remittances, G20).
- zsh does not word-split `$var` in `set -- $p` loops: write each upload command out (or use the orchestrator).

## 2026-10-19 — Rehearsal 2: entity 1693 with `onboard.rb next --run` only

Orios again onto a fresh entity (1693 / fund 379), every step run by `onboard.rb next --run` — no hand-typed commands (the
fund, form types, approve + verify and distribution approvals that were holes in rehearsal 1 are steps of it now).
**10,992 / 10,992 ✅**; it stopped by itself at investor access. Step times: unit settings 12 s, investors 70 s,
commitments 89 s, calls 14 s, remittances 173 s, payments 429 s, approve + verify 221 s, distributions 14 s, distribution
payments 408 s, approvals 19 s, units 423 s, recon 27 s.

- **A closed laptop pauses the run and the sign-in token (1 hour) expires**: units failed with HTTP 401 after ops closed the
  lid mid-run. `onboard.rb` now checks the token before any step and says "sign in again"; then `next --run` resumed at
  units without redoing anything — "done" is read from the app. For long runs use a longer-lived token from Profile ›
  API tokens. Step banners now carry the clock time, so a gap shows where it came from.
- `status` also catches stale builds: Inflexor's yml edited after the build → step 3 ▶ until rebuilt.

## 2026-10-19 — Fund-ops review of the Orios run (feedback) — what 10,992 green checks missed

A fund-ops reviewer found three faults; all three were still in the tools and confirmed on rehearsal fund 379, which the
recon had passed 10,992 / 10,992.

1. **Capital calls were invented.** The MIS has drawdowns per investor; grouping "each investor's 1st, 2nd …" into calls made
   "Drawdown 1st" span 2013–2021 (due 2021-04-05) while "Drawdown 2nd" was due 2016-01-11 — not a fund event, and out of
   chronology. *Rule:* a call is a real fund-level event (a common notice date / a client call id). If the source cannot
   say which drawdowns form a call, **flag it as a client question — do not invent the grouping.** Check call chronology
   (call dates and due dates in sequence order, due ≥ call date).
2. **Payment references were invented** ("MIS 001D Drawdown 1st") — not in the prompt or the data. *Rule:* never create values
   the client did not give; optional fields stay blank; a placeholder only where the importer requires a value, marked and
   asked about.
3. **TDS was stored as custom fields**, so the platform's net payable = gross: 1,410 of 1,795 payments, ₹32,55,59,037.60 =
   total TDS. *Rule:* model money the platform's way — TDS as **account entries**, linked by a **distribution fee of type
   "tax"**, then **recompute** the distribution. A custom field holding money that changes a payout is a smell.
4. **The recon was circular**: it compared the app with values we wrote (our call grouping, our TDS/net custom fields), not
   the client's figures with what the platform **computes and shows investors** (`net_payable`, call dates). *Rule:* the
   recon reads platform-computed figures and checks business logic, and go-live also needs a fund-ops reviewer's sign-off.

## 2026-10-19 — Orios rerun after the fund-ops review (entity 1694 / fund 380, `onboard.rb` only)

Calls from a demo schedule (17 periods of payment dates, approved by ops as check-data assumption C10), TDS through account
entries + "Tax" fees + recompute, no generated references. **11,497 / 11,497 ✅** with the non-circular recon: calls one event
each and in date order (17/17, 16/16), platform net payable = client net and gross − net = client TDS on all 1,795 payments,
515 references blank, 128 folios' balance units = the MIS. Gate: go-live blocked on the client's must-haves and M14.

- **Lists page at 10 unless asked:** `/capital_calls.json` needs `all=true` (17 calls → only 10 returned; the done-check
  failed although the upload succeeded); `/import_uploads.json` ignores `all=true` entirely (G41) — filter by
  `q[import_type_eq]`. Always pass `all=true` and re-count.
- **One remittance per folio per call:** when a folio has several drawdowns (payments) inside one call, merge them into one
  remittance (called = sum, payments kept) — CapHive refuses a second ("Folio has already been taken"; 26 rows of upload 2717).
  The partial upload was undone with the app's per-upload undo (ops approved), then re-uploaded.
- Step times: remittances 75 s, payments 144 s, approve + verify 97 s, distribution payments 156 s, TDS entries 67 s,
  TDS fees + recompute 205 s, units 535 s, recon 8 s.

## 2026-10-20 — Portfolio + KPI steps in `onboard.rb`, validated on Inflexor (dev, entity 1631)

Generalised the Inflexor-only scripts into `tools/portfolio/` driven by `mappings/portfolio.yml`, and added steps 20–31 to
`onboard.rb` (`--portfolio` follows only that track). Validation: rebuilt companies / investments / valuations / 142 mappings equal
the files imported on 19 Oct; steps 20–26 read ✔ from the app alone; portfolio recon 259/259; then the 41 KPI reports were deleted
through the API (ops-approved) and steps 27–31 re-ran them end to end: dry runs 90 / 626 / 56 ok cells, 0 mismatches → 772 stored,
all tied to source cells → approved → **908 KPIs** (99 / 753 / 56, the same as before), 136 computed = Σ components.

- **Check labels against the MIS before building mappings — mechanically.** The generic label check found a mapping that had been
  silently blank since 19 Oct: Revspot "Invoiced Revenue" was scoped to "FY27 YTD P&L", whose rows say "Invoiced Revenue (Overall)"
  and "True Invoiced Revenue (Excludes reraised)". A dry run cannot show this (an unmatched label is just "kpi_missing"). The builder
  now stops on any label not on its source sheet; `pending_labels:` (with a question) keeps it while the client decides.
- **The importer squeezes double spaces in labels** ("Gross Profit / (Loss)  [Revenue …]" is stored with one space). Compare mapping
  names with whitespace collapsed — the reader ignores whitespace anyway.
- **A KPI Info sheet may start at column B.** Roo's `row()` counts from the first used column; name columns as Excel shows them
  and read with `cell(r, c)`.
- **Steps that wait on client answers must not block independent work.** The fund recon fails by design (C9, references), so the
  portfolio steps got their own track instead of waiting behind it.
- **Editing a payment un-verifies its remittance (G44)** — even a reference-only PATCH. The fund's collected amount drops to 0 until
  the call is bulk-verified again. After any payment edit: bulk Verify, wait for the count to settle, compare the fund summary
  with its value before the edit. (Inflexor C7: 68 references cleared → 54 remittances unverified → re-verified, totals restored.)
