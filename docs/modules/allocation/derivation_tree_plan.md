# Derivation Tree — Implementation Plan

**For:** the agent that will build and test this. Self-contained: read this, then the files it
names. Background and the reasoning behind the feature are in
[Understanding an Allocation Run — Proposals](allocation_run_review_proposals.md), proposal 1.

**Status:** Built, then **retired** — replaced by the entry page's "How this was worked out" card (`AccountEntryExplanation`); see the proposals doc. Kept as a record of the design. Differences from this plan, which was written before the screen was chosen:

- It hangs off the **Account Entries Period Report**, not the Allocation Run Checker.
- `FormulaReferenceScanner::HelperCall` names its member `helper`, not `method` — a Struct
  member called `method` overrides `Object#method`.
- A `:fact` node carries `raw_value`, not `amount_cents`, and is **not** formatted as money.
  The breakdown stores whatever an intermediate step evaluated to, and nothing distinguishes a
  sum of `amount_cents` from a year or a month count; formatting all of them as currency turned
  `end_date.year` = 2024 into "20.24". Only nodes that really are entry amounts show money.
- Tests are `features/fund/derivation_tree.feature` +
  `features/step_definitions/derivation_tree.rb`.

## What is being built

A page that starts at one account entry — e.g. a folio's `NAV` for a run — and lets a fund
employee open it into the numbers it was computed from, and those into theirs, until they reach
something that is not computed: a payment, an uploaded entry, a plain database figure.

```
NAV                                         9,41,500
 ├─ Capital Collected as on Date           10,00,000
 │    └─ capital_commitment.capital_remittance_payments…sum   10,00,000   (fact)
 ├─ Since Inception Management Fees           23,500
 │    └─ since inception of "Management Fees"                 23,500
 │         ├─ Management Fees · 30 Jun 2026                   10,000
 │         └─ Management Fees · 30 Sep 2026                   13,500   ▸ opens further
 ├─ Since Inception Operating Cost            15,000
 …
```

Today the entry page (`account_entries/show.html.erb`, from line 183) already shows **one
level** of working: the formula text and a table of intermediate values. This feature makes
each of those values a door to the entry behind it.

## Facts you need (verified against the code and production data)

**What an entry stores about how it was computed.** `AccountEntry#explanation` is a serialized
Array written in `CreateAccountEntry#eval_formula`
(`app/packs/allocation_engine/account_entry_allocation/create_account_entry.rb:69-75`):

- element 0 — always the formula text that was evaluated. This is a **snapshot**; use it, not
  `fund_formula.formula`, which may have been edited since.
- then the formula's description, **only if it has one**.
- then a JSON object of `expression => value` (the "breakdown"), **only if** the run had
  "Explain Formulas" on **and** the formula's own `explain` flag is set.

So the array has 1, 2 or 3 elements. Find the breakdown the way the show view does: the element
that parses as a JSON Hash. Never index by position.

Breakdown keys are source expressions, e.g. `"@since_inception_management_fees": "23500.0"`,
and also partial sums such as `"@a - @b": "…"`. Values are strings, in cents.

**How formulas refer to other entries — two ways, and the existing code only knows one.**

1. `@field` references. `@net_income` means "this folio's entry named Net Income, computed
   earlier in this run". The name ↔ field transform is `FundFormula.to_varable_name`
   (`fund_formula.rb:301`) — use it, do not re-implement it. `FundFormula#interpolate_formula`
   (`:267`) extracts the `@` names and accepts `eval_string:` so it can scan the snapshot text.
   About 90% of enabled formulas use this.
2. **By name string, through helper calls** on the commitment — roughly a third of enabled
   formulas (production counts: `since_inception(` 311, `year_to_date(` 276, `quarterly(` 273,
   `account_entries.where` 522, of 3,918). The helpers are in
   `app/packs/funds/capital_commitments/models/concerns/commitment_account_entry.rb`:

   | Call | Sums this folio's non-cumulative entries matching name / entry_type… |
   |---|---|
   | `quarterly(name, entry_type, _start, end_date)` — alias `period` | from `end_date.beginning_of_quarter` to `end_date` |
   | `year_to_date(name, entry_type, _start, end_date)` | see the method for its year start |
   | `since_inception(name, entry_type, start, end_date, …)` | everything up to `end_date` |
   | `on_date(name, entry_type, end_date)` — alias `as_on_date` | on `end_date` only |

   Either `name` or `entry_type` may be `nil`. All take `sqlite: true` by default — **outside a
   run you must pass `sqlite: false`**, or they read a scratch database that no longer exists.

   `FundFormula#referenced_field_names` and `FundFormulaDependencyGraph` see only way 1. If the
   tree did the same, `Since Inception Management Fees` would look like a raw fact instead of a
   sum you can open. Handling way 2 is the core of this work.

**Names that are not entries.** `@fund`, `@start_date`, `@end_date`
(`AllocationBaseOperation::ENGINE_PROVIDED_FIELDS`) and the commitment base fields
(`CommitmentCache::BASE_FIELDS`: `remittances_collected`, `distributions`, `units`, …) are
inputs, not entries. Show them as facts; do not look for an entry behind them.

**Entries the engine derives on its own.** When a formula has `generate_ytd_qtly`, the engine
also writes `Quarterly X`, `YTD X` and `Since Inception X` with a synthesised formula like
`capital_commitment.quarterly('X', nil, @start_date, @end_date) + x`
(`create_account_entry.rb:98-140`). The trailing bare `x` is a **local variable** holding this
run's `X`, not an `@` reference — treat a bare identifier equal to
`to_varable_name(<some entry name on this folio and date>)` as a reference to that entry.

**Other shapes of entry.**

- `Allocate*` rule types split a fund-level entry across folios. The folio entry has
  `parent_type: "AccountEntry"` and `parent_id` pointing at the fund-level source. Show that
  source as a child ("share of …").
- `Percentage` rule type stores **no explanation at all** (the amount is precomputed in
  `ComputeCustomPercentage`). Show it as a leaf with a one-line note.
- Uploaded / manual entries have `generated: false`, no `fund_formula_id`, and usually an
  `import_upload_id`. They are leaves: "uploaded".
- Fund-level rollups (`capital_commitment_id IS NULL`, `cumulative: true`) are the sum of the
  folio entries of the same name for the run. Children = those folio entries (see "Fund-level
  roots" below).

**Finding an entry.** `account_entries` is partitioned by `reporting_date` with a composite
primary key. Always look entries up with both `id` and `reporting_date`
(see `AccountEntriesController#set_account_entry`, line 196) and carry `reporting_date` in
every link, as `explain_account_entry_path(entry, reporting_date: …)` already does.

## Decisions already made (flag to the user if you think one is wrong — do not silently change)

1. **Employees only.** `AccountEntryPolicy#show?` also admits investors. The tree exposes the
   fund's formulas, so add `derivation?` returning `permissioned_employee?` only.
2. **Lazy, one level at a time.** Opening a node fetches just that node's children (Turbo
   Frame). Never build the whole tree — a 427-formula fund would be thousands of queries.
3. **Use what was stored; do not re-evaluate formulas.** Node values come from the stored
   breakdown and from the child entries themselves. No `eval`, no `reparse_and_save` here.
   (Re-evaluating would show today's answer, not the run's.)
4. **Show disagreement rather than hiding it.** If the breakdown says `@x` was 23,500 but the
   entry named X now holds 25,000, show both with a "changed since the run" marker. That is a
   finding the reviewer wants.
5. **Be honest about what could not be read.** A helper call whose name argument is a variable,
   not a string literal, cannot be resolved from text. Show it as a fact with its value and the
   note "chosen at run time" — never guess.
6. **Folio-level first.** Fund-level roots get the simple folio listing described below and
   nothing more.

## Build order

### Step 1 — `FormulaReferenceScanner` (pure text → references)

New PORO, `app/packs/funds/funds/services/formula_reference_scanner.rb`. Input: formula text.
Output: a struct with

- `field_names` — from `@` references (delegate to `interpolate_formula` logic; exclude
  engine-provided and base fields into a separate `input_names` list),
- `helper_calls` — `[{ method:, name:, entry_type:, source: }]` for calls to `quarterly`,
  `period`, `year_to_date`, `since_inception`, `on_date`, `as_on_date` where the first two
  arguments are string or `nil` literals; `source` is the exact source text of the call so it
  can be matched to a breakdown key,
- `name_filters` — entry names found as string literals (or arrays of them) in a
  `where(name: …)` on `account_entries`,
- `unresolved` — source text of helper calls whose arguments were not literals,
- `bare_identifiers` — lower-case identifiers used as values (for the derived-sibling case).

Parse with the `parser` gem — `FundFormula#parse_statement` (`fund_formula.rb:356`) already
does, follow its setup. Text that fails to parse returns an empty result with `parse_error`
set; it must never raise. No database access in this class.

### Step 2 — `AccountEntryDerivation` (one entry → its children)

New PORO, same directory. `AccountEntryDerivation.new(entry).children` returns an array of
`Node` structs: `kind` (`:entry`, `:aggregate`, `:fact`, `:input`, `:source_entry`,
`:uploaded`, `:unresolved`), `label`, `amount_cents`, `entry_id`, `reporting_date`,
`expression`, `note`, `run_value_cents` (value recorded at run time, when it differs),
`expandable`.

Resolution, in this order:

1. Not generated → no children; the entry itself is rendered as `:uploaded`.
2. `parent_type == "AccountEntry"` → a `:source_entry` child for the parent.
3. Scan `explanation.first` with the scanner.
4. **Sibling lookup, once per call:** load this folio's entries on this `reporting_date` —
   `select(:id, :reporting_date, :name, :entry_type, :amount_cents, :generated, :cumulative)`
   only — and index them by `FundFormula.to_varable_name(name)`. One query; tens of rows.
   Each `field_name` and matching bare identifier becomes an `:entry` node. A field with no
   sibling becomes a `:fact` with the breakdown value and the note "no entry found".
5. Each `helper_call` becomes an `:aggregate` node; value from the breakdown key equal to its
   `source`, else computed by calling the helper with `sqlite: false`. It is expandable: its
   children are the folio's non-cumulative entries in that helper's window (mirror the
   helper's own `where`; narrow `select` as above), newest first, each an `:entry` node.
6. Each `name_filter` becomes an `:aggregate` labelled "entries named …", children = that
   folio's entries with that name up to the entry's date, with the note "the formula applies
   its own filter — this list may be wider than what it summed".
7. Every remaining breakdown key that is not a partial sum of the above becomes a `:fact`
   (expression text + value). No breakdown stored → a single note node: "This run was made
   without Explain Formulas; intermediate values were not recorded."

Guards: pass the path of entry ids down through the links and refuse to expand an id already
in it (cycle); stop at depth 15.

**Fund-level roots.** For a fund-level rollup entry, children = the folio entries of that
name and run, largest absolute amount first, first 25, with a count of the rest and a link to
the filtered account entries list (build the link the way `_allocation_runs.html.erb:184`
does). Aggregate in SQL; do not load all folios.

### Step 3 — Controller, routes, views

- Routes (`config/routes/fund.rb`, inside `resources :account_entries`):
  `get :derivation, on: :member` and `get :derivation_children, on: :member`.
- `AccountEntriesController#derivation` renders the page for the root entry;
  `#derivation_children` renders one node's children inside a Turbo Frame. Both reuse
  `set_account_entry` and authorize with `derivation?`. `derivation_children` also takes
  `kind`, and for aggregates the helper `method`/`name`/`entry_type`, plus the `path`.
- Views under `account_entries/`: `derivation.html.erb`, `_derivation_node.html.erb`,
  `_derivation_children.html.erb`. Plain server-rendered nested list, Bootstrap classes as in
  the rest of the modernize layout. No new JS controller unless Turbo Frames cannot do it.
- Amounts: render through the same money formatting the show page uses for the entry amount.
  Dates through `l(date)` — see the date rules in `CLAUDE.md`.
- Entry points: a "How was this computed?" button on `account_entries/show.html.erb` beside
  the existing AI-explain button, shown when `policy(entry).derivation?`.

### Step 4 — Tests (Cucumber only — this project has no RSpec; do not add specs)

New `features/fund/derivation_tree.feature` and
`features/step_definitions/derivation_tree_steps.rb`. Reuse the Background and run/entry steps
from `features/fund/allocation_run_checker.feature` and
`features/step_definitions/allocation_run_checker.rb`. Entries can be created directly with a
hand-written `explanation`; you do not need to run the engine.

Scanner (no browser, in the style of `features/ai/mcp_server/mcp_ontology.feature`), as a
Scenario Outline over formula text → expected references:

- `@a - @b` → fields a, b
- `@fund.id + @end_date.year` → no fields, inputs only
- `capital_commitment.since_inception("Management Fees", nil, @start_date, @end_date)` → one helper call
- `capital_commitment.quarterly(nil, "Operating Cost", @start_date, @end_date)` → entry_type form
- `capital_commitment.since_inception(some_name, nil, …)` → unresolved
- `capital_commitment.account_entries.where(name: "Management Fees", reporting_date: ..@end_date).sum(:amount_cents)` → name filter
- the derived-sibling text `capital_commitment.quarterly('X', nil, @start_date, @end_date) + x`
- text that is not valid Ruby → empty result, no exception

Derivation and page:

- an entry whose formula references two sibling entries shows both, with their amounts
- opening a since-inception aggregate lists the entries in its window, and one of those opens further
- an entry with no breakdown shows the "without Explain Formulas" note and still resolves `@` references
- a stored run-time value that differs from the entry now shows the "changed since the run" marker
- an `Allocate*` entry shows its fund-level source
- an uploaded entry is a leaf
- a `Percentage` entry is a leaf with its note
- a cycle does not loop
- an investor cannot open the derivation page; a company admin can
- a fund-level rollup lists its folio entries, capped, with the link to the rest

### Running and verifying

- The test database is **SQLite**, production is MySQL: write queries with ActiveRecord, no
  database-specific SQL.
- Always prefix: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/derivation_tree.feature`.
  Redis must be up on `localhost:6379`. Run only the new feature and
  `features/fund/allocation_run_checker.feature` (shared steps), not the whole suite.
- The user's standing preference is that Cucumber runs start on their say-so — ask before the
  first run; until then verify with `bin/rails runner` and `bundle exec rubocop` on touched files.
- Do not commit. Leave the work in the tree on branch `allocation-run-review-proposals`.

## Guardrails (from `CLAUDE.md` — these have caused production incidents)

- `account_entries` is very large. Every query must be bounded by folio **and** date (or by
  run), and must `select` only the narrow columns listed above — never load `json_fields`,
  `notes` or `explanation` for a list of entries. `explanation` is read for **one** entry: the
  node being opened.
- No `present?`/`blank?` on relations; no `pluck(...).uniq`; no `includes(:account_entries)`.
- No migration is needed for this feature. If you find yourself writing one, stop and ask.

## Out of scope

- The folio check — the fund's own figures beside ours (proposal 2) — and the fund totals sheet
  ([plan](fund_totals_sheet_plan.md)). The totals sheet links *into* this page; whichever is
  built second adds that link.
- Links from facts to their source records (payments, valuations). Facts show expression and
  value only.
- Teaching `FundFormulaDependencyGraph` about name-string references. Worth doing later with
  the same scanner; not now.
- Any AI.

## Done when

- A company admin can open a folio's generated entry, press "How was this computed?", and walk
  at least three levels down through both `@` references and a `since_inception`/`quarterly`
  call to uploaded or fact leaves.
- Every scenario above passes; rubocop is clean on touched files; no new query loads wide
  columns for more than one entry.
