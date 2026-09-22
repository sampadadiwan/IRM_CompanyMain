# Fund Totals Sheet — Implementation Plan

**For:** the agent that will build and test this. Self-contained: read this, then the files it
names. Background is in
[Understanding an Allocation Run — Proposals](allocation_run_review_proposals.md), proposal 3.

**Status:** Built. Differences from this plan, which was written before the screen was chosen:

- It is a **tab on the Account Entries Period Report**, not a page on the Allocation Run
  Checker, and it is fetched lazily so a reviewer who only wants the summary never pays for it.
- Rows are grouped by entry **name** only, not by (name, entry_type): they are folded out of
  `AccountEntryReport#name_date_totals`, which groups by name, so grouping any finer would cost
  another scan of `account_entries` to answer a question nobody asked.
- `AccountEntryReportPage#filter_selected?` now accepts a bare `allocation_run_id`. It did not
  before, so the "View Report" link on the allocation screen — the one a reviewer follows to see
  what a run produced — landed on a filter form and showed nothing. **This changes an existing
  screen's behaviour.**
- The detail pivot is built only when a folio, entry name or entry type is chosen
  (`explicit_filters?`): a pivot of every name against every folio in a run is unreadable.
- Tests are `features/fund/fund_totals_tie_out.feature` +
  `features/step_definitions/fund_totals_tie_out.rb`.

## What is being built

Funds review a run in two steps: first they check the **fund totals** against their own
spreadsheet, then they validate a few folios. This page is step one, and it is where a review
starts.

One row per entry name the run produced: the system's fund total, a box for the fund's own
figure, and the difference. A row that disagrees opens into the folios that make up the total.

```
Fund totals · run 1 Jul – 30 Sep 2026                System         Yours        Diff
Capital Collected as on Date                   42,50,00,000  42,50,00,000          0   ✓
Management Fees                                   21,25,000     21,25,000          0   ✓
Since Inception Management Fees                   63,75,000          —             —
Operating Cost                                     8,40,000      8,10,000    +30,000   ▸ folios
NAV                                            41,12,35,000  41,12,65,000    −30,000   ▸ folios
```

Note that the period figure (`Management Fees`) and the since-inception figure
(`Since Inception Management Fees`) are **different entry names and therefore different
rows**. The fund fills in whichever rows its spreadsheet has; empty rows are simply not tied
out. The page does not need to know which kind of total the fund keeps.

## Facts you need (verified against the code and production data)

- The reviewable object is `AllocationRun`
  (`app/packs/funds/funds/models/allocation_run.rb`): `fund_id`, `entity_id`, `start_date`,
  `end_date`, `status`, `locked`, `rule_for`. Every entry a run generates carries
  `allocation_run_id` and `reporting_date = run.end_date`.
- **Re-running a period makes a new `AllocationRun` and hard-deletes the previous attempt's
  entries** (`RunFormulas#delete_existing_primary_entries`, `run_formulas.rb:821`). This is why
  the fund's figures must not be keyed to the run — see "Storing the fund's figures".
- Fund totals exist in two forms. Formulas that generate an entry per folio also get a stored
  fund-level rollup (`capital_commitment_id IS NULL`, `cumulative: true`) via
  `RollupAsFundAccountEntry`. Some results exist **only** at fund level (e.g. fund-wide
  portfolio numbers). Folio entries are `capital_commitment_id IS NOT NULL`,
  `cumulative: false`.
- Checker finding 2.1 (`AllocationRunReportBuild#check_fund_totals`,
  `allocation_run_report_build.rb:301`) already verifies stored fund rollup = sum of folios.
  Do not re-implement that check here; link to it.
- Runs created before `AllocationRunReportBuild::ENTRY_TAGGING_STARTED_ON` (2025-03-29) have
  no `allocation_run_id` on their entries. Reuse that constant.
- The runs list is `app/packs/funds/funds/views/funds/_allocation_runs.html.erb`; per-run
  buttons are around lines 184-211. `AllocationRunsController` and `AllocationRunPolicy`
  already exist.
- Amounts are stored in cents as `decimal(30,8)`; the fund's currency is `fund.currency`.

## Decisions already made (flag to the user if you think one is wrong — do not silently change)

1. **The sheet covers what this run produced** — entries carrying its `allocation_run_id`.
2. **A row's system total** is the sum of the run's folio entries for that
   `(name, entry_type)`; where the run produced no folio entries for it, the fund-level entry's
   amount. If both exist and differ by more than the checker's `AMOUNT_EPSILON`, show a small
   warning on the row linking to the run's checker report — do not try to explain it here.
3. **The fund's figures belong to the fund and the date, not to the run.** A re-run must find
   the figures already typed in.
4. **"Matches" means equal when both are rounded to 2 decimal places in major units** — if the
   two numbers look the same on screen, the row is a match. No per-fund tolerance setting.
5. **Figures are typed in by hand in this version.** Uploading the fund's workbook is proposal
   4, separate work. Build the storage so an upload can fill the same records later.
6. **Employees only**, same as the rest of the allocation screens.
7. **Rows appear in the fund's own formula order** (`fund_formulas.sequence`), not
   alphabetically — that is the order the fund's staff think in. Entries whose formula is gone
   sort last.

## Storing the fund's figures — new model `TieOutFigure`

Table `tie_out_figures`:

| Column | Type | Notes |
|---|---|---|
| `entity_id`, `fund_id` | bigint, not null | |
| `capital_commitment_id` | bigint, null | `NULL` = a fund total. Present so the folio check (proposal 2) can reuse this table without a migration. |
| `as_of_date` | date, not null | the run's `end_date` |
| `name` | string(125), not null | entry name |
| `entry_type` | string(60) | |
| `amount_cents` | decimal(30,8), not null | the fund's figure |
| `user_id` | bigint, not null | who entered it last |
| `notes` | text | |
| timestamps | | |

Index on `(fund_id, as_of_date, capital_commitment_id, name)`. Enforce one figure per
`(fund_id, as_of_date, capital_commitment_id, name, entry_type)` with a model uniqueness
validation and `find_or_initialize_by` on save — do **not** rely on a unique index, because
MySQL treats `NULL` `capital_commitment_id`s as distinct, and do not add a MySQL-only generated
column (the test database is SQLite). Follow a neighbouring model for `belongs_to`, `monetize`
and auditing conventions; these figures are evidence of a sign-off, so they should be audited
if neighbouring fund models are.

**Migration caveat — important.** The local development database lags the committed schema,
so `bin/rails db:migrate` rewrites `db/schema.rb` and `db/schema_test.rb` with ~120 unrelated
lines removed. After migrating: `git checkout db/schema.rb db/schema_test.rb`, add only the
new table to `schema.rb` by hand (alphabetical table order, bump the version), run
`bin/rails db:clean_schema` to regenerate `schema_test.rb`, and confirm `git diff` shows
additions only.

## Build order

### Step 1 — `AllocationRunTotals` service

New PORO, `app/packs/funds/funds/services/allocation_run_totals.rb`.
`AllocationRunTotals.new(run).rows` returns row structs: `name`, `entry_type`, `rule_for`,
`system_cents`, `folio_count`, `fund_level_cents`, `rollup_mismatch`, `figure`
(`TieOutFigure` or nil), `diff_cents`, `state` (`:match`, `:differs`, `:not_entered`),
`sequence`.

Exactly three queries, all grouped in SQL, none loading entry rows:

1. folio totals — the run's entries with a folio, `cumulative: false`, bounded by
   `fund_id`, `entity_id`, `allocation_run_id` **and** `reporting_date: run.end_date`
   (the date bound lets MySQL prune partitions), grouped by
   `name, entry_type, rule_for, fund_formula_id` → sum of `amount_cents` and count of distinct
   folios;
2. fund-level entries for the same run, grouped the same way;
3. the fund's `TieOutFigure`s for `as_of_date = run.end_date` with no folio.

Plus one small `FundFormula.where(id: …).pluck(:id, :sequence)` for ordering. Write the
aggregates with ActiveRecord/Arel so they run on SQLite and MySQL alike.

`AllocationRunTotals#folios(name:, entry_type:)` for the breakdown: the run's folio entries
for that row, `select`ing only `id, reporting_date, capital_commitment_id, commitment_name,
amount_cents`, largest absolute amount first, **first 50**, plus the total count. Resolve
`folio_id`s with one `CapitalCommitment.where(id: …).pluck(:id, :folio_id)`.

### Step 2 — Controllers and routes

In `config/routes/fund.rb`, inside `resources :allocation_runs`:
`get :totals, on: :member` and `get :total_folios, on: :member`; and
`resources :tie_out_figures, only: %i[create update destroy]`.

- `AllocationRunsController#totals` — the sheet. `#total_folios` — the breakdown for one row,
  rendered in a Turbo Frame under the row.
- `TieOutFiguresController` — saves one figure and replies with a Turbo Stream that re-renders
  just that row (system, yours, diff, state). Accept the amount in **major units** as typed
  (`8,10,000` or `810000.50`; strip separators) and store cents. Blank input deletes the figure.
- New `TieOutFigurePolicy`; employees with access to the fund only. Figures on a **locked**
  run's date stay editable — locking protects the entries, not the fund's own notes.

### Step 3 — Views

- `allocation_runs/totals.html.erb`: header (fund, period, run status, checker badge linking
  to the report if one exists), a summary line — "12 of 40 rows entered · 10 match · 2 differ"
  — then the table. A filter for Accounting / Reporting (`rule_for`) and a "show only rows that
  differ" toggle. Rows that differ are visually distinct; rows not entered are quiet.
- The "Yours" cell is an inline form that saves on blur/Enter. Reuse an existing Stimulus
  controller for auto-submit if the app has one before writing a new one.
- The folio breakdown lists folio, amount and share of the total, with "showing 50 of N" and a
  link to the full filtered account entries list (build it as
  `_allocation_runs.html.erb:184` does). Each folio row links to that entry — and, once the
  [derivation tree](derivation_tree_plan.md) exists, to its derivation page. Whichever of the
  two features is built second adds that link.
- Empty states: run not successful → say so and link to the checker; run predates entry
  tagging → explain that its entries cannot be attributed to it.
- Add a **Totals** button to each run row in `_allocation_runs.html.erb` beside the existing
  entries / report / check buttons, shown by policy.
- Amounts via the app's money helpers in the fund's currency; dates via `l(date)` (see the
  date rules in `CLAUDE.md`).

### Step 4 — Tests (Cucumber only — this project has no RSpec; do not add specs)

New `features/fund/fund_totals_sheet.feature` and
`features/step_definitions/fund_totals_sheet_steps.rb`. Reuse the Background and the
"finished allocation run" / "the run produced …" steps from
`features/fund/allocation_run_checker.feature` and
`features/step_definitions/allocation_run_checker.rb`.

- the sheet lists one row per entry name with the sum of the folio entries
- a result that exists only at fund level still gets a row
- rows follow the fund formulas' sequence
- entering a figure equal to the system total marks the row as matching
- entering a different figure shows the signed difference and marks the row as differing
- figures that differ only beyond 2 decimal places count as a match
- an amount typed with thousands separators is understood
- clearing a figure removes it
- the summary line counts entered / matching / differing rows
- opening a differing row lists its folios, largest first, capped at 50 with the count of the rest
- **a re-run of the same period shows the figures entered against the earlier run**
- a stored fund rollup that disagrees with its folios shows the warning linking to the checker
- a run that did not succeed, and a run older than entry tagging, show their empty states
- an investor cannot open the sheet or save a figure; a company admin can
- the runs list shows the Totals button

### Running and verifying

- The test database is **SQLite**, production is MySQL — no database-specific SQL.
- Always prefix: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/fund_totals_sheet.feature`.
  Redis must be up on `localhost:6379`. Run only the new feature and
  `features/fund/allocation_run_checker.feature` (shared steps), not the whole suite.
- The user's standing preference is that Cucumber runs start on their say-so — ask before the
  first run; until then verify with `bin/rails runner` and `bundle exec rubocop` on touched files.
- Do not commit. Leave the work in the tree on branch `allocation-run-review-proposals`.

## Guardrails (from `CLAUDE.md` — these have caused production incidents)

- `account_entries` is very large. Totals are computed by `GROUP BY` in the database; the only
  entry rows ever loaded are the ≤ 50 of one breakdown, with narrow `select`s. Never load
  `json_fields`, `notes` or `explanation` here.
- No `present?`/`blank?` on relations; no `pluck(...).uniq`; no `includes(:account_entries)`.

## Out of scope

- Uploading the fund's workbook and any AI (proposal 4).
- The folio check inside the derivation tree (proposal 2) — the table is ready for it;
  the screens are not part of this work.
- Comparing with the previous period, anomaly flags, or any judgement about whether a number
  is reasonable.
- Changing the checker.

## Done when

- A company admin can open Totals for a run, type the fund's figures, see which rows match and
  which differ, open a differing row to its folios, and find the figures still there after the
  period is re-run.
- Every scenario above passes; rubocop is clean on touched files; `git diff` on the schema
  files shows only the new table.
