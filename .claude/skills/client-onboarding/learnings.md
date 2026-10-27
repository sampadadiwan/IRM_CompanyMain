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

## 2026-10-20 — Demo Fund 2 (dev, entity 1695 / fund 381): quarterly capital-account pack, no dates

Source: a QR workbook ("9.Comvsrecd": 275 folios × 15 drawdown columns, total received, arrears) and a Master sheet
(Circulation: distributions net + TDS per FY, units, capital-account heads). No drawdown, payment or distribution dates at all.

- **New layout `call_columns`** (read_drawdowns.rb + fund_recon.rb): one amount column per call, dates from `calls.schedule`,
  the folio's total received spread oldest-first (`assumptions.payment_allocation`, excess on the last call). Distributions can
  come from a second sheet keyed by folio (`distributions.source`); a group value may be `{value: …}` or `{sum: [cols]}`.
- **Place undated calls with the client's own cumulative figures.** The "check sheet" (received at Mar-24/Jun-25/Sep-25/Dec-25)
  put calls 1–10 before Mar-24 and 11–15 in FY 25-26: calls 11–15 − arrears + arrears open at Mar-25 = the YTD Paid column to
  the rupee. Still placeholders (client question), but the order is proven.
- **Roo's `sheet(name)` returns the same object** (it switches the default sheet). `a = book.sheet("X"); b = book.sheet("Y")`
  makes `a` read Y. Open one workbook object per sheet. A cross-check against the client's own columns caught it at once.
- **Units are issued on min(called, collected)** per verified remittance (`CapitalRemittance#pending_amount_for_units_allocation`);
  over-paid folios get fewer units than a client that issues on money received. fund_recon ⑦ now expects min(called, received).
- **`onboard.rb` step 15 is "done" after ANY AccountEntry upload** (`uploaded_ok.("AccountEntry")`). Upload other account
  entries (capital-account heads) only after step 15, or it skips the TDS entries.
- **Capital-account heads (ops):** set-up fee, management fee, operating expenses, other income as account entries in two parts —
  since inception till the previous quarter-end (since inception − quarter) and the latest quarter — so they add up to the
  client's since-inception figure. Entry types follow `public/sample_uploads/account_entries.xlsx` (Fees / Setup Fees,
  Expense / Management Fees …). Realised / unrealised gains: not loaded that way (ops).
- **Manual review of every upload file (hard rule 10)**, asked by ops mid-run: `tools/review.rb`. Waived for Demo Fund 2 only.
- `GET /fund_unit_settings.json` answers 406 — fee rates per class cannot be read back (G45).
- Timings (dev): investors 275 in 279 s, commitments 260 s, remittances 4,118 in 871 s, payments 4,109 in 1,027 s.
- **Bulk verify can stop partway with no error the API shows.** 15 calls × 275 remittances queued (HTTP 202 each); the jobs
  stopped at the same folio in every call (~20:58: folios in order verified up to IN301, 2,009 / 4,109 verified), the verified
  count stayed flat, and `onboard.rb` printed no ✔. Per-record failures go only to an error email (sandbox inbox), not the API.
  Diagnose from the data (whole folios in order = interrupted job; scattered = per-record refusals), then re-run step 12 — Verify
  only picks unverified remittances, so the retry is safe (it verified the 2,109 left in 190 s).
- **Poll with server-side filters, proven first.** Waiting loops re-read whole lists (4,118 remittances, ~2 s each); a filtered
  poll is ~0.1 s. Proven against the full list: remittances `q[verified_eq]`, `q[collected_amount_gt]`, `capital_call_id=`;
  distribution payments `capital_distribution_id=` — but **`q[capital_distribution_id_eq]` is silently ignored** (all 808 rows
  came back). Before adding any filter, compare its count with a count from the unfiltered list (and try a bogus `q[...]`).
- **The builder verified unpaid remittances** (`verified_on_import` wrote Yes on every row; earlier clients had no unpaid
  drawdowns). Fixed: Verified = Yes only with a payment. The 9 on fund 381 were toggled off with `PATCH /capital_remittances/:id/verify.json`.
- **Count, don't list, for "done" checks.** Fund lists send `total-count` to API callers; `api.count(path)` reads it with
  `per_page=1`. `onboard.rb status` went 28.7 s → 2.0 s (the payments list alone was 24.9 s, only to be counted). The sandbox
  guard now re-reads the entity at most once a minute (it was one GET per write), and upload polling backs off 5 → 30 s.

## 2026-10-21 — Demo Fund 2 on staging (entity 1548, fund 363): a second fund in an entity that already has one

- **Upload done-checks must be fund-scoped.** Import uploads are owned by the entity (`owner_type "Entity"`), so
  `onboard.rb`'s `uploaded_ok("FundUnitSetting")` saw the Orios fund's upload and skipped unit settings for the new fund.
  It now counts only uploads created after the fund. Any new done-check on `/import_uploads.json` needs the same bound.
- Reusing an existing `CapitalCommitment` form type works when its tag matches "Form Tag" — the form-type JSON does not show
  the tag, so the commitment upload's 0 failed is the proof.

## 2026-10-22 — Windows setup for BU users

- **Portable across OSes (for BU users on Windows):** client-workspace scripts used `require_relative` with an absolute Linux
  path to the tools, which broke on any other machine. They now `require "api"` and run as `ruby -I "<tools>" scripts/x.rb`;
  tools launch each other with `RbConfig.ruby`, and `doctor.rb` checks a machine's setup before the first step.
- **`review.rb approve` needs a terminal** on stdin plus a typed `yes`, so `ruby` commands can run without a permission
  prompt (`allowed-tools: Bash(ruby:*)` in SKILL.md) and the agent still cannot approve its own files.

## 2026-10-27 — Review and sandbox checks moved into `Api#call`

- **The review check lived only in the `api.rb upload` CLI**, so a workspace script calling
  `api.call("post", "/import_uploads.json", multipart: …)` sent an unapproved file, and any caller could pass `guard: false`
  to skip the sandbox check. Now `Api#call` runs the review check on every `/import_uploads` post (with or without `.json`;
  no file attached → refused), and `guard:` is gone: the one write allowed before sandbox is on is `Api#sandbox_on!`, and
  the raw request (`send_request`) is private. Logos (`/documents.json`) and KPI workbooks (`/kpi_reports.json`) are not
  review-checked — they are not in the review dump and have their own checks.
- Still open: a plain JSON write (`api.call("post", "/capital_remittances.json", body: …)`) cannot be traced to a reviewed
  file, so only `onboard.rb`'s own JSON posts check their source file.

## 2026-10-27 — Progress display, hints, and no second upload while one is importing

- **`onboard.rb` held back every tool's output until the tool exited** (`Open3.capture3`), so a 17-minute payments import
  showed nothing — not even "upload created" — until the end. Tools now stream (`popen2e`, `$stdout.sync` in `ui.rb`) and
  `api.rb upload` prints the import's progress from `processed_row_count` / `failed_row_count` / `total_rows_count`. The
  app saves those counts every 10 rows (`ImportUtil#process_rows`), and `total_rows_count` from the start
  (`ImportServiceBase`), so the bar is live while the import runs.
- **A rerun mid-import would have uploaded the file again.** A step's "done" (e.g. payments in app ≥ rows in file) is false
  until the import ends, so running the step again during it sent a second upload. `api.rb upload` now looks for an
  upload with the same name still `running` and watches it instead. Proven on the local app (2026-10-27, Demo Fund 2,
  entity 1695): a second `upload` started 8 s after the first printed "👀 Watching upload 2733" and no second upload exists.
- The watch now ends only when nothing has moved for 10 minutes (exit 2, with a Sidekiq / dead-job hint), not after a fixed
  20 minutes, so a long import that keeps moving is followed to the end. `api.rb upload` reports through its exit code;
  the old `outcome="…" failed=0` line is gone.
- Known errors get a 💡 hint (`tools/hints.yml`). Re-uploading 1,200 existing payments failed every row with "Skipping: a
  payment for folio … already exists" — the importer refuses existing payments, so nothing changed.
- **Review fixes (same day).** A total of 0 crashed the progress line (verify with nothing left); an expired token while
  watching looked like "queued" and blamed Sidekiq (now 🔑 and exit 1); a job that died showed "running" for a day and
  blocked resending (now `--resend <id>`, ops' call); post-processing after the last row looked stalled (now "finishing up",
  30 min); `"POST"`, `/import_uploads/` and `//import_uploads.json` slipped past the review check (now one normalised
  route); hints printed twice. Upload names now end `· <fund or client>`, so two funds in one entity don't watch each
  other's uploads — which exposed an older bug: the multipart body joined UTF-8 text with the binary file, so any non-ASCII
  file name crashed the upload (now built as bytes). The results-file link is no longer printed (a pre-signed S3 URL with
  an access key id). Tested on the local app: uploads 2734 (sent), 2734 again (watched, not resent), 2735 (`--resend 2734`),
  2736 (token swapped mid-watch → 🔑) — all 1,200 rows refused as existing payments, no data changed.

## 2026-10-27 — Review approval moved into the session

- **The terminal-only approval was too much for ops** (Orios live run): a second terminal, a long path, 15 `yes` prompts —
  and the first attempt left no `approved.yml` at all (run where stdin is not a terminal). Ops: "approval should be from
  here". Now Claude shows `review.rb summary` and asks a question in the session; on ops' answer it runs
  `review.rb approve --all --by <ops> --via "<ops' answer>"`. The guarantee moved from code (the TTY check) to the rule
  (Claude records only ops' answer, rule 6-style); `via:` in `review/approved.yml` keeps each approval traceable.

## 2026-10-27 — Orios live run (dev, entity 1971 / fund 382), ops watching in the session

- From the bare entity to a passing fund recon in **28 minutes of run time** (08:52 sandbox → 09:21 recon), every step by
  `onboard.rb next --run`, 0 failed rows anywhere: **11,497 / 11,497 recon checks ✅**. Step times: fund 1 s, unit
  settings 16 s, form types 1 s, investors 36 s, commitments 36 s, calls 16 s, remittances 1 min 7 s, payments 1 min 37 s,
  approve + verify 1 min 19 s, distributions 17 s, distribution payments 2 min 40 s, TDS entries 1 min 8 s, TDS fees +
  recompute 2 min 22 s, approve distributions 6 s, units 8 min 36 s (17 allocations + 7 redemptions, ~24 s each to settle),
  recon 7 s. Uploads 2737–2745.
- Review approval in the session (one question, "Approve all 15") replaced the terminal approval mid-run — the first
  terminal attempt had recorded nothing.
- Watching the run through a Monitor: per-call `approve …` / `verify …` lines tripped the event-rate limit; filter to step
  banners, ⏳ milestones and ✅ / 🎉 / 🛑 / 🐢 / ⚠️ lines only. Stopping the Monitor would stop the run (the run is its command).
- **Report and sounds (same day, ops' ask).** The run report is now a step (32, "Run report") that only Claude can finish:
  it stays open until `report.md` is newer than every recon and carries each recon's marker line, so a recon re-run
  reopens it; every `next --run` appends to `out/onboard_run.log` (escape codes stripped) as the report's Log source.
  Every step ends with a sound — chosen by ear with ops: the short freedesktop `message` / `dialog-error` were inaudible,
  so "needs you" and "failed" play ~1 s sounds twice (`message-new-instant`, `suspend-error`); "done" is `complete` once.
- **Sounds, final (same day).** The system sounds differed per OS and two were inaudible, so the tools ship their own
  (`tools/sounds/*.wav`, generated by `make_sounds.rb`): a doorbell for "needs you" and a low falling pair for "failed".
  Ops kept the freedesktop `complete` for "done" — played from the system theme where installed, never copied into the
  repo (the theme mixes CC-BY, CC-BY-SA and GPL), with a generated chime as the fallback elsewhere.
- **The "one drawdown event" recon check could not fail** (found writing the Orios live report). It measured the spread
  of the app's remittance dates per call, but the builder gives every remittance its call's date, so the spread was
  always 0 and the 09:21 recon showed 17 / 17 ✅ on a demo grouping. `fund_recon.rb` now measures the client's own
  drawdown dates per call from the source (before same-call drawdowns merge; the "Various" folios' assumed date left
  out). Re-run: 11,489 / 11,497 — 8 of 17 Orios demo calls span 35–356 days. *Rule:* a check that compares the app with
  values the builder wrote is circular (same lesson as 2026-10-19 ④) — check against the source, then prove the check
  can fail.
- **Second review (before the PR).** Fixed: a network error while watching an upload crashed it instead of counting
  toward the 10-minute stall; an `abort` inside a step (review, sandbox) skipped the "Not done" line, hints, sound and
  log entry; `approve --all` re-listed the files at approve time, so a file rebuilt after ops' answer got approved —
  now `summary` prints a code for the exact files and hashes, and `approve --all --summary <code>` refuses any change;
  a job Sidekiq had not picked up yet looked "settled" after 10 s (verify and recompute now wait 2 minutes for the
  first change); uploads sent under the pre-2026-10-27 name were not found by the never-twice check; the run log
  wrote every one-second redraw as its own line; an empty sheet showed "-1 rows"; a `'` in a Windows path broke the sound.
